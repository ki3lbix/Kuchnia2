#!/usr/bin/env bash
set -euo pipefail

CS_URL="${1:-}"
if [[ -z "$CS_URL" ]]; then
  echo "Usage: psql-migrate.sh <CONNECTION_URL>" >&2
  exit 1
fi

# Utwórz tabelę historii migracji (idempotentnie)
psql "$CS_URL" -v "ON_ERROR_STOP=1" <<'SQL'
CREATE TABLE IF NOT EXISTS schema_migrations (
  id           serial primary key,
  filename     text    not null unique,
  sha256       text    not null,
  applied_at   timestamptz not null default now(),
  applied_by   text    not null default current_user
);
SQL

shopt -s nullglob
MIG_DIR="db/migrations"
APPLIED=0

for f in "$MIG_DIR"/*.sql; do
  base="$(basename "$f")"
  # oblicz sha256 treści pliku
  if command -v sha256sum >/dev/null 2>&1; then
    sum="$(sha256sum "$f" | awk '{print $1}')"
  else
    sum="$(shasum -a 256 "$f" | awk '{print $1}')"
  fi

  # sprawdź, czy plik już zastosowany z tą samą sumą
  EXISTS=$(psql "$CS_URL" -tA -v "ON_ERROR_STOP=1" \
    -c "SELECT 1 FROM schema_migrations WHERE filename=$$${base}$$ AND sha256=$$${sum}$$ LIMIT 1;")
  if [[ "$EXISTS" == "1" ]]; then
    echo "== Skipping already applied: $base"
    continue
  fi

  echo "== Applying: $base"
  # transakcja per plik; ON_ERROR_STOP=1 — fail przy 1. błędzie
  psql "$CS_URL" -v "ON_ERROR_STOP=1" <<SQL
BEGIN;
\i $f
INSERT INTO schema_migrations(filename, sha256) VALUES ('$base', '$sum');
COMMIT;
SQL

  APPLIED=$((APPLIED+1))
done

echo "== Done. Applied: $APPLIED migration(s)."
