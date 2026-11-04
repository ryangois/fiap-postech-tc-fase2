# ToggleMaster - Tech Challenge Fase 2

Plataforma de feature flags dividida em 5 microsserviços, rodando em Docker localmente e em Kubernetes (EKS) na AWS.

| Serviço | Linguagem | Porta | Dados |
|---|---|---|---|
| auth-service | Go | 8001 | PostgreSQL (`auth_db`) |
| flag-service | Python | 8002 | PostgreSQL (`flags_db`) |
| targeting-service | Python | 8003 | PostgreSQL (`targeting_db`) |
| evaluation-service | Go | 8004 | Redis, publica no SQS |
| analytics-service | Python | 8005 | consome o SQS, grava no DynamoDB |

## Rodando local

```bash
cp .env.example .env
docker compose up -d --build
docker compose ps
```

Sobem 9 containers: os 5 serviços, 2 PostgreSQL, Redis e DynamoDB Local. O `dynamodb-init` só cria a tabela e sai.

- `postgres-auth` tem o `auth_db`, e `postgres-shared` tem `flags_db` e `targeting_db`. Os `db/init.sql` rodam na primeira subida.
- A chave que o evaluation-service usa (`SERVICE_API_KEY`) já é inserida no banco do auth, então não precisa criar na mão.
- Não tem SQS local. O compose usa a fila da AWS definida em `AWS_SQS_URL`. Sem ela, o evaluation só loga os eventos.
- O analytics grava no DynamoDB Local via `AWS_ENDPOINT_URL_DYNAMODB`.

Teste:

```bash
K=tm_key_local_dev_evaluation_service
curl -X POST localhost:8002/flags -H "Authorization: Bearer $K" -H "Content-Type: application/json" \
  -d '{"name":"enable-new-dashboard","description":"novo dashboard","is_enabled":true}'
curl -X POST localhost:8003/rules -H "Authorization: Bearer $K" -H "Content-Type: application/json" \
  -d '{"flag_name":"enable-new-dashboard","is_enabled":true,"rules":{"type":"PERCENTAGE","value":50}}'
curl "localhost:8004/evaluate?user_id=user-123&flag_name=enable-new-dashboard"
```

Itens gravados no DynamoDB Local:

```bash
docker compose run --rm --no-deps --entrypoint aws dynamodb-init \
  dynamodb scan --table-name ToggleMasterAnalytics --endpoint-url http://dynamodb-local:8000
```

## Kubernetes

```
k8s/
├── kustomization.yaml
├── secrets.env.example
├── auth/         namespace, configmap, secret, job-db-init, deployment, service, ingress
├── flag/         namespace, configmap, secret, job-db-init, deployment, service, ingress
├── targeting/    namespace, configmap, secret, job-db-init, deployment, service, ingress
├── evaluation/   namespace, serviceaccount, configmap, secret, deployment, service, ingress, hpa
├── analytics/    namespace, serviceaccount, configmap, secret, deployment, service, hpa
└── optional/keda-analytics.yaml
```

Os `secret.yaml` são gerados pelo `scripts/gen-secrets.sh` e não vão pro Git.

- Cada serviço tem o próprio namespace (`tm-auth`, `tm-flag`, `tm-targeting`, `tm-evaluation`, `tm-analytics`). A comunicação entre eles é pelo DNS do cluster, ex.: `auth-service.tm-auth.svc.cluster.local`.
- Os Deployments têm requests/limits, readiness e liveness em `/health`, rodam como não-root e com filesystem read-only.
- Secrets (base64): URLs do RDS, Redis e SQS, tabela do DynamoDB, `MASTER_KEY` e `SERVICE_API_KEY`. ConfigMaps: URLs internas, porta e região.
- Os Jobs `*-db-init` aplicam o `init.sql` de cada serviço no RDS, usando o arquivo que já está na imagem. O do auth também insere a `SERVICE_API_KEY`.
- Rotas do Ingress (nginx): `/validate` e `/admin` vão pro auth, `/flags` pro flag-service, `/rules` pro targeting e `/evaluate` pro evaluation. O analytics é worker e não é exposto.
- HPA por CPU (70%): evaluation de 2 a 10 réplicas, analytics de 1 a 6.
- Na conta pessoal, o analytics escala pelo tamanho da fila com KEDA (`k8s/optional/keda-analytics.yaml`), de 0 a 10 pods.

## Infra na AWS

Recursos (conta pessoal, opção B). O cluster foi criado com eksctl e o resto com a AWS CLI:

- EKS criado com eksctl (`eksctl/cluster.yaml`): node group (mín. 1, desejado 2, máx. 4), add-on Pod Identity e as roles dos pods
- 5 repositórios no ECR, um por serviço
- 2 RDS PostgreSQL: um com o `auth_db` e outro com o `flags_db` e o `targeting_db` (ver abaixo)
- 1 ElastiCache Redis
- tabela `ToggleMasterAnalytics` no DynamoDB (chave `event_id`, String)
- 1 fila SQS Standard

Os security groups do RDS e do Redis liberam 5432 e 6379 só para a rede do cluster (192.168.0.0/16).

Sobre os bancos: o enunciado pede 3 RDS, mas a conta está no free plan da AWS, que barra a criação de mais de 2 instâncias de RDS ("maximum number of instances available with free plan accounts"). Por isso o targeting-service ficou na mesma instância do flag-service, mas com database próprio (`targeting_db`), sem compartilhar tabelas. Numa conta sem essa restrição é só criar a terceira instância e trocar a `TARGETING_DATABASE_URL`. Pelo mesmo motivo os nós são `c7i-flex.large`, que é elegível ao free tier.


Cluster (trocar o id da conta no yaml antes):

```bash
eksctl create cluster -f eksctl/cluster.yaml
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"=nlb
helm install keda kedacore/keda -n keda --create-namespace
```

Deploy:

```bash
./scripts/push-ecr.sh v1
cp k8s/secrets.env.example k8s/secrets.env   # preencher com os endpoints
./scripts/gen-secrets.sh
kubectl apply -k k8s/
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

Sem access key nos pods: as roles vêm do EKS Pod Identity, criadas pelo eksctl a partir do `cluster.yaml`.

| ServiceAccount | Permissões |
|---|---|
| `tm-evaluation/evaluation-service` | `sqs:SendMessage` na fila |
| `tm-analytics/analytics-service` | `sqs:ReceiveMessage`, `sqs:DeleteMessage`, `sqs:GetQueueAttributes` na fila e `dynamodb:PutItem` na tabela |
| `keda/keda-operator` | `sqs:GetQueueAttributes` na fila |

No AWS Academy não dá pra criar role. Ali os pods usam a LabRole dos nós e o analytics fica com o HPA por CPU.

## Teste de carga

```bash
# evaluation
kubectl run loadgen -n tm-evaluation --image=williamyeh/hey --restart=Never -- \
  -z 120s -c 50 "http://evaluation-service.tm-evaluation.svc.cluster.local:8004/evaluate?user_id=u1&flag_name=enable-new-dashboard"
kubectl get hpa -n tm-evaluation -w

# analytics
./scripts/sqs-flood.sh 1000
kubectl get pods -n tm-analytics -w
```

## Ajustes no código recebido

O código original não compilava. Fiz só o necessário:

| Serviço | Problema | Ajuste |
|---|---|---|
| auth-service | `go.mod` pedia `pgx/v4/stdlib` (é pacote, não módulo) e faltava `go.sum` | removi a linha e gerei o `go.sum` |
| auth-service | imports não usados (`fmt`, `crypto/sha256`, `encoding/hex`) | removidos |
| auth-service | `pgx/v4/stdlib` importado sem uso | virou import em branco (`_`) para registrar o driver |
| evaluation-service | `go.sum` corrompido | regenerado com `go mod tidy` |
| evaluation-service | `os` usado sem import e `context` sem uso | imports corrigidos |
| flag, targeting, analytics | Flask 2.2.2 não funciona com Werkzeug 3 | fixei `Werkzeug==2.2.2` |
| analytics-service | boto3 1.26 não aceita endpoint por variável de ambiente | atualizei para 1.35.99 |

## Imagens

Dockerfiles multi-stage. Go compila estático em `golang:1.22-alpine` e roda em `alpine:3.20`. Python instala as dependências num venv e copia pra `python:3.11-slim`. Todas rodam como não-root e têm healthcheck.
