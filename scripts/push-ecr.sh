#!/usr/bin/env bash
# build e push das imagens pro ecr
# uso: ./scripts/push-ecr.sh [tag]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:-v1}"
REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
SERVICES=(auth-service flag-service targeting-service evaluation-service analytics-service)

echo ">> Registry: $REGISTRY  Tag: $TAG"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

for svc in "${SERVICES[@]}"; do
  aws ecr describe-repositories --region "$REGION" --repository-names "$svc" >/dev/null 2>&1 \
    || aws ecr create-repository --region "$REGION" --repository-name "$svc" \
         --image-scanning-configuration scanOnPush=true >/dev/null

  # nós são x86, evita imagem arm se buildar no mac
  docker build --platform linux/amd64 -t "$REGISTRY/$svc:$TAG" "$ROOT/$svc"
  docker push "$REGISTRY/$svc:$TAG"
done

sed -i.bak -E \
  -e "s#newName: [0-9]+\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/#newName: $REGISTRY/#" \
  -e "s#newTag: .*#newTag: $TAG#" \
  "$ROOT/k8s/kustomization.yaml"
rm -f "$ROOT/k8s/kustomization.yaml.bak"
echo ">> k8s/kustomization.yaml atualizado para $REGISTRY (tag $TAG)"
