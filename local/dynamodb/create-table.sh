#!/bin/sh
# tabela do analytics no dynamodb local
set -e
ENDPOINT=http://dynamodb-local:8000
TABLE=ToggleMasterAnalytics

echo "Aguardando DynamoDB Local..."
until aws dynamodb list-tables --endpoint-url "$ENDPOINT" >/dev/null 2>&1; do sleep 1; done

if aws dynamodb describe-table --table-name "$TABLE" --endpoint-url "$ENDPOINT" >/dev/null 2>&1; then
  echo "Tabela $TABLE já existe."
  exit 0
fi

aws dynamodb create-table \
  --endpoint-url "$ENDPOINT" \
  --table-name "$TABLE" \
  --attribute-definitions AttributeName=event_id,AttributeType=S \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST >/dev/null

echo "Tabela $TABLE criada."
