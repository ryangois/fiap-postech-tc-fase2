#!/bin/sh
# cria targeting_db e aplica os schemas
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -c "CREATE DATABASE targeting_db;"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname flags_db -f /sql/flags.sql
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname targeting_db -f /sql/targeting.sql
