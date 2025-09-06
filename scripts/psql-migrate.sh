#!/usr/bin/env bash
set -euo pipefail

CS_URL="${1:-}"
if [[ -z "$CS_URL" ]]; then
  echo "Usage: psql-migrate.sh <CONNECTION_URL>" >&2
  exit 1
fi

# Funkcja: SQL-quoting (zamienia ' -> '' aby bezpiecznie zacytować do SQL-a)
sql_quote() {
  local s="${1:-}"
  printf "%s" "${s//\'/\'\'}"
}

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

  # 2) SHA-256 pliku
  if command -v sha256sum >/dev/null 2>&1; then
    sum="$(sha256sum "$f" | awk '{print $1}')"
  else
    sum="$(shasum -a 256 "$f" | awk '{print $1}')"
  fi

  # 3) Sprawdź historię (cytujemy literały samodzielnie)
  base_q="$(sql_quote "$base")"
  sum_q="$(sql_quote "$sum")"

  EXISTS="$(psql "$CS_URL" -tA -v "ON_ERROR_STOP=1" \
    -c "SELECT 1 FROM schema_migrations WHERE filename = '$base_q' AND sha256 = '$sum_q' LIMIT 1;")"

  if [[ "$EXISTS" == "1" ]]; then
    echo "== Skipping already applied: $base"
    continue
  fi

  echo "== Applying: $base"
  # 4) Transakcja per plik + zapis do historii
  psql "$CS_URL" -v "ON_ERROR_STOP=1" <<SQL
BEGIN;
\i $f
INSERT INTO schema_migrations(filename, sha256) VALUES ('$base_q', '$sum_q');
COMMIT;
SQL

  APPLIED=$((APPLIED+1))
done

echo "== Done. Applied: $APPLIED migration(s)."
