#!/usr/bin/env bash
set -euo pipefail

CS_URL="${1:-}"
if [[ -z "$CS_URL" ]]; then
  echo "Usage: psql-migrate.sh <CONNECTION_URL>" >&2
  exit 1
fi

# 1) Tabela historii migracji (idempotentnie)
psql "$CS_URL" -v "ON_ERROR_STOP=1" <<'SQL'
CREATE TABLE IF NOT EXISTS schema_migrations (
  id         serial PRIMARY KEY,
  filename   text NOT NULL UNIQUE,
  sha256     text NOT NULL,
  applied_at timestamptz NOT NULL DEFAULT now(),
  applied_by text NOT NULL DEFAULT current_user
);
SQL

shopt -s nullglob
MIG_DIR="db/migrations"
APPLIED=0

for f in "$MIG_DIR"/*.sql; do
  base="$(basename "$f")"

  # 2) Oblicz sumę SHA-256 pliku (dla audytu i idempotencji)
  if command -v sha256sum >/dev/null 2>&1; then
    sum="$(sha256sum "$f" | awk '{print $1}')"
  else
    sum="$(shasum -a 256 "$f" | awk '{print $1}')"
  fi

  # 3) Sprawdź, czy dokładnie ten plik (ta sama suma) był już zastosowany
  EXISTS="$(psql "$CS_URL" -tA -v "ON_ERROR_STOP=1" \
    -v f="$base" -v s="$sum" \
    -c "SELECT 1 FROM schema_migrations WHERE filename = :'f' AND sha256 = :'s' LIMIT 1;")"

  if [[ "$EXISTS" == "1" ]]; then
    echo "== Skipping already applied: $base"
    continue
  fi

  echo "== Applying: $base"
  # 4) Transakcja per plik + zapis do historii (z parametryzacją :'var')
  psql "$CS_URL" -v "ON_ERROR_STOP=1" -v f="$base" -v s="$sum" <<SQL
BEGIN;
\i $f
INSERT INTO schema_migrations(filename, sha256) VALUES (:'f', :'s');
COMMIT;
SQL

  APPLIED=$((APPLIED+1))
done

echo "== Done. Applied: $APPLIED migration(s)."
