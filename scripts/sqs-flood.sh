#!/usr/bin/env bash
# manda mensagens de teste pra fila, em lotes de 10
# uso: ./scripts/sqs-flood.sh [quantidade]
set -euo pipefail

TOTAL="${1:-500}"
QUEUE_URL="${AWS_SQS_URL:?defina AWS_SQS_URL}"

echo ">> Enviando $TOTAL mensagens para $QUEUE_URL"
sent=0
while (( sent < TOTAL )); do
  entries=""
  for (( i = 0; i < 10 && sent < TOTAL; i++, sent++ )); do
    if (( RANDOM % 2 )); then result=true; else result=false; fi
    body="{\"user_id\":\"demo-user-$sent\",\"flag_name\":\"enable-new-dashboard\",\"result\":$result,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
    entries+="{\"Id\":\"m$sent\",\"MessageBody\":\"${body//\"/\\\"}\"},"
  done
  aws sqs send-message-batch --queue-url "$QUEUE_URL" --entries "[${entries%,}]" --output text --query 'length(Successful)' >/dev/null
  printf '\r   %d/%d' "$sent" "$TOTAL"
done
echo
echo ">> Pronto. Mensagens visíveis na fila:"
aws sqs get-queue-attributes --queue-url "$QUEUE_URL" \
  --attribute-names ApproximateNumberOfMessages --query 'Attributes.ApproximateNumberOfMessages' --output text
