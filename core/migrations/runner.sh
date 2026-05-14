#!/bin/bash
# runner.sh — migrations versionadas para startup-pack
# Uso: DATABASE_URL=postgres://... bash runner.sh [--dry-run]
# IMPORTANTE: ejecutar desde la raíz del repo para que \i resuelva correctamente

set -euo pipefail

# Siempre ejecutar desde la raíz del repo — independiente de desde dónde se llame
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

DB_URL="${DATABASE_URL:-}"
if [[ -z "$DB_URL" ]]; then
  echo "ERROR: DATABASE_URL no definida" >&2
  exit 1
fi

MIGRATIONS_DIR="$REPO_ROOT/core/migrations/sql"
SCHEMA_SQL="$REPO_ROOT/blueprints/base/004_schema_versions.sql"

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

# Fix: usar find + sort en lugar de ls en for loop (safe con espacios en paths)
while IFS= read -r FILE; do
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
done < <(find "$MIGRATIONS_DIR" -maxdepth 1 -name "*.sql" | sort)

echo ""
echo "=== Resultado: $TOTAL total | $PENDING aplicadas | $FAILED fallidas ==="
echo "=== Root: $REPO_ROOT ==="
