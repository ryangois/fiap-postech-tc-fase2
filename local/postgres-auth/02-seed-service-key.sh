#!/bin/sh
# chave do evaluation-service. o auth guarda só o sha256
set -e

psql -v ON_ERROR_STOP=1 -v key="$SERVICE_API_KEY" \
  --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'SQL'
INSERT INTO api_keys (name, key_hash)
VALUES ('evaluation-service', encode(sha256(convert_to(:'key', 'UTF8')), 'hex'))
ON CONFLICT (key_hash) DO NOTHING;
SQL
