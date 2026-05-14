#!/bin/bash
# runner.sh — migrations versionadas para startup-pack
# Uso: DATABASE_URL=postgres://... bash runner.sh [--dry-run]
#      DATABASE_URL=postgres://... bash runner.sh --rollback=N  (revierte hasta versión N, exclusive)
# IMPORTANTE: ejecutar desde la raíz del repo para que \i resuelva correctamente

set -euo pipefail

# Siempre ejecutar desde la raíz del repo — independiente de desde dónde se llame
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

DRY_RUN=false
ROLLBACK_TO=""

for arg in "$@"; do
  case "$arg" in
    --dry-run)   DRY_RUN=true ;;
    --rollback=*) ROLLBACK_TO="${arg#--rollback=}" ;;
  esac
done

DB_URL="${DATABASE_URL:-}"
if [[ -z "$DB_URL" ]]; then
  echo "ERROR: DATABASE_URL no definida" >&2
  exit 1
fi

MIGRATIONS_DIR="$REPO_ROOT/core/migrations/sql"
DOWN_DIR="$REPO_ROOT/core/migrations/sql/down"
SCHEMA_SQL="$REPO_ROOT/blueprints/base/004_schema_versions.sql"

psql() { command psql "$DB_URL" "$@"; }

# ── ROLLBACK MODE ──────────────────────────────────────────────────────────────
if [[ -n "$ROLLBACK_TO" ]]; then
  echo "=== startup-pack ROLLBACK hasta versión $ROLLBACK_TO ==="
  echo "DB: ${DB_URL%%@*}@***"
  echo ""

  # Obtener versiones aplicadas en orden descendente
  APPLIED=$(psql -t -c "SELECT version FROM schema_versions ORDER BY version DESC;" | tr -d ' ')

  REVERTED=0
  for VERSION in $APPLIED; do
    # Parar al llegar al target (el target se queda aplicado)
    [[ "$VERSION" -le "$ROLLBACK_TO" ]] && break

    DOWN_FILE="$DOWN_DIR/${VERSION}_down.sql"
    if [[ ! -f "$DOWN_FILE" ]]; then
      echo "  ✗ [$VERSION] — down script no encontrado: $DOWN_FILE" >&2
      exit 1
    fi

    echo -n "  ↓ [$VERSION] rollback ... "
    if $DRY_RUN; then
      echo "(dry-run)"
      continue
    fi

    if psql -q -f "$DOWN_FILE"; then
      psql -q -c "DELETE FROM schema_versions WHERE version = '$VERSION';"
      echo "OK"
      REVERTED=$((REVERTED + 1))
    else
      echo "FAILED"
      echo "ERROR: rollback falló en $VERSION — abortando" >&2
      exit 1
    fi
  done

  echo ""
  echo "=== Rollback completo: $REVERTED versiones revertidas ==="
  echo "=== Root: $REPO_ROOT ==="
  exit 0
fi

# ── FORWARD MODE (default) ─────────────────────────────────────────────────────

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
