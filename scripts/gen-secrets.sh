#!/usr/bin/env bash
# gera os k8s/*/secret.yaml a partir do k8s/secrets.env
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${1:-$ROOT/k8s/secrets.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Arquivo $ENV_FILE não encontrado. Copie k8s/secrets.env.example para k8s/secrets.env e preencha." >&2
  exit 1
fi

# lê sem source, as urls têm ? e &
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  [[ -z "$line" || "$line" == \#* || "$line" != *=* ]] && continue
  key="${line%%=*}" val="${line#*=}"
  val="${val%\"}"; val="${val#\"}"
  printf -v "$key" '%s' "$val"
done < "$ENV_FILE"

b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

# write_secret <dir> <servico> CHAVE=VAR_DO_ENV... (vazias ficam de fora)
write_secret() {
  local dir="$1" name="$2"; shift 2
  local out="$ROOT/k8s/$dir/secret.yaml"
  {
    echo "# gerado pelo scripts/gen-secrets.sh"
    echo "apiVersion: v1"
    echo "kind: Secret"
    echo "metadata:"
    echo "  name: $name-secret"
    echo "  namespace: tm-$dir"
    echo "type: Opaque"
    echo "data:"
    for pair in "$@"; do
      local key="${pair%%=*}" src="${pair#*=}"
      local val="${!src:-}"
      if [[ -n "$val" ]]; then
        echo "  $key: $(b64 "$val")"
      fi
    done
  } > "$out"
  echo "gerado: k8s/$dir/secret.yaml"
}

AWS_CREDS=(AWS_ACCESS_KEY_ID=AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN=AWS_SESSION_TOKEN)

write_secret auth       auth-service       DATABASE_URL=AUTH_DATABASE_URL MASTER_KEY=MASTER_KEY SERVICE_API_KEY=SERVICE_API_KEY
write_secret flag       flag-service       DATABASE_URL=FLAG_DATABASE_URL
write_secret targeting  targeting-service  DATABASE_URL=TARGETING_DATABASE_URL
write_secret evaluation evaluation-service REDIS_URL=REDIS_URL SERVICE_API_KEY=SERVICE_API_KEY AWS_SQS_URL=AWS_SQS_URL "${AWS_CREDS[@]}"
write_secret analytics  analytics-service  AWS_SQS_URL=AWS_SQS_URL AWS_DYNAMODB_TABLE=AWS_DYNAMODB_TABLE "${AWS_CREDS[@]}"
