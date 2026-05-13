#!/bin/bash
# runner.sh — migrations versionadas para startup-pack
# Uso: DATABASE_URL=postgres://... bash runner.sh [--dry-run]

set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

DB_URL="${DATABASE_URL:-}"
if [[ -z "$DB_URL" ]]; then
  echo "ERROR: DATABASE_URL no definida" >&2
  exit 1
fi

MIGRATIONS_DIR="$(dirname "$0")/sql"
SCHEMA_SQL="$(dirname "$0")/../../blueprints/base/004_schema_versions.sql"

psql() { command psql "$DB_URL" "$@"; }

# Asegurar tabla de control
psql -q -f "$SCHEMA_SQL" 2>/dev/null || true

# Obtener versiones ya aplicadas
APPLIED=$(psql -t -c "SELECT version FROM schema_versions ORDER BY version;" | tr -d ' ')

echo "=== startup-pack migration runner ==="
echo "DB: ${DB_URL%%@*}@***"
echo ""

TOTAL=0
PENDING=0
FAILED=0

for FILE in $(ls "$MIGRATIONS_DIR"/*.sql 2>/dev/null | sort); do
  FILENAME=$(basename "$FILE")
  VERSION="${FILENAME%%_*}"
  NAME="${FILENAME%%.sql}"
  CHECKSUM=$(sha256sum "$FILE" | awk '{print $1}')

  TOTAL=$((TOTAL + 1))

  if echo "$APPLIED" | grep -qx "$VERSION"; then
    echo "  ✓ [$VERSION] $NAME — ya aplicada"
    continue
  fi

  PENDING=$((PENDING + 1))

  if $DRY_RUN; then
    echo "  ~ [$VERSION] $NAME — pendiente (dry-run)"
    continue
  fi

  echo -n "  → [$VERSION] $NAME ... "

  if psql -q -f "$FILE"; then
    psql -q -c "INSERT INTO schema_versions (version, name, checksum)
                VALUES ('$VERSION', '$NAME', '$CHECKSUM')
                ON CONFLICT (version) DO NOTHING;"
    echo "OK"
  else
    echo "FAILED"
    FAILED=$((FAILED + 1))
    echo "ERROR: falló $FILENAME — abortando" >&2
    exit 1
  fi
done

echo ""
echo "=== Resultado: $TOTAL total | $PENDING aplicadas | $FAILED fallidas ==="
