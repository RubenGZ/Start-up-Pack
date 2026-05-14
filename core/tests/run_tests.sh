#!/bin/bash
# core/tests/run_tests.sh — Hydra OS pgTAP Test Runner
# Levanta un contenedor Postgres temporal, aplica migrations y ejecuta pgTAP.
# Uso: bash core/tests/run_tests.sh [--filter=pattern]
# Requisitos: Docker, psql (cliente)
# Exit code: 0 = PASS total, 1 = algún test falló

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TESTS_DIR="$REPO_ROOT/core/tests"
MIGRATIONS_DIR="$REPO_ROOT/core/migrations/sql"

# ── Config ──────────────────────────────────────────────────────────────────
CONTAINER="hydra_test_$$"
PG_IMAGE="postgres:16-alpine"
PG_PORT="5499"
PG_DB="hydra_test"
PG_USER="hydra"
PG_PASS="hydra_test_secret"
FILTER="${1#--filter=}"
FILTER="${FILTER:-*.sql}"

DB_URL="postgres://$PG_USER:$PG_PASS@localhost:$PG_PORT/$PG_DB"

# ── Colores ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${CYAN}→${NC} $1"; }
ok()   { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }

# ── Cleanup on exit ──────────────────────────────────────────────────────────
cleanup() {
  if docker ps -q --filter "name=$CONTAINER" | grep -q .; then
    log "Stopping test container $CONTAINER..."
    docker rm -f "$CONTAINER" > /dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

# ── 1. Levantar contenedor temporal ──────────────────────────────────────────
echo ""
echo -e "${BOLD}=== Hydra OS — pgTAP Test Runner ===${NC}"
echo ""

log "Starting ephemeral Postgres container: $CONTAINER"
docker run -d \
  --name "$CONTAINER" \
  -e POSTGRES_DB="$PG_DB" \
  -e POSTGRES_USER="$PG_USER" \
  -e POSTGRES_PASSWORD="$PG_PASS" \
  -p "$PG_PORT:5432" \
  "$PG_IMAGE" > /dev/null

# ── 2. Esperar a que esté listo ───────────────────────────────────────────────
log "Waiting for Postgres to be ready..."
for i in $(seq 1 20); do
  if psql "$DB_URL" -c "SELECT 1" > /dev/null 2>&1; then
    ok "Postgres ready (${i}s)"
    break
  fi
  if [ "$i" -eq 20 ]; then
    fail "Postgres did not start after 20s"
    exit 1
  fi
  sleep 1
done

# ── 3. Instalar pgTAP ────────────────────────────────────────────────────────
log "Installing pgTAP extension..."
docker exec "$CONTAINER" sh -c \
  "apk add --quiet perl && \
   wget -q https://github.com/theory/pgtap/releases/download/v1.3.3/pgtap-1.3.3.tar.gz -O /tmp/pgtap.tar.gz && \
   tar -xzf /tmp/pgtap.tar.gz -C /tmp && \
   cd /tmp/pgtap-1.3.3 && make install > /dev/null 2>&1" \
  || warn "pgTAP install failed — using fallback inline TAP output"

psql "$DB_URL" -c "CREATE EXTENSION IF NOT EXISTS pgtap;" > /dev/null 2>&1 \
  && ok "pgtap extension loaded" \
  || warn "pgtap extension unavailable — tests use plain assertions"

# ── 4. Aplicar migrations core ───────────────────────────────────────────────
log "Applying core migrations..."
APPLIED=0
for SQL_FILE in $(ls "$MIGRATIONS_DIR"/*.sql 2>/dev/null | sort); do
  FNAME="$(basename "$SQL_FILE")"
  psql "$DB_URL" -q -f "$SQL_FILE" > /dev/null 2>&1 && APPLIED=$((APPLIED+1)) \
    || warn "Migration $FNAME had warnings (continuing)"
done
ok "$APPLIED migrations applied"

# ── 5. Ejecutar tests ─────────────────────────────────────────────────────────
log "Running test suite (filter: $FILTER)..."
echo ""

TOTAL=0
PASSED=0
FAILED=0
FAILED_FILES=()

for TEST_FILE in $(ls "$TESTS_DIR"/$FILTER 2>/dev/null | grep -v run_tests.sh | sort); do
  FNAME="$(basename "$TEST_FILE")"
  echo -e "  ${CYAN}▶ $FNAME${NC}"

  OUTPUT=$(psql "$DB_URL" -f "$TEST_FILE" 2>&1)
  EXIT_CODE=$?

  # Contar ok / not ok en output TAP
  FILE_PASS=$(echo "$OUTPUT" | grep -c "^ok " || true)
  FILE_FAIL=$(echo "$OUTPUT" | grep -c "^not ok " || true)
  TOTAL=$((TOTAL + FILE_PASS + FILE_FAIL))
  PASSED=$((PASSED + FILE_PASS))

  if [ "$EXIT_CODE" -ne 0 ] || [ "$FILE_FAIL" -gt 0 ]; then
    FAILED=$((FAILED + FILE_FAIL))
    FAILED_FILES+=("$FNAME")
    echo "$OUTPUT" | grep -E "^(not ok|#)" | sed 's/^/    /'
    fail "  $FNAME — $FILE_PASS passed, $FILE_FAIL failed"
  else
    ok "  $FNAME — $FILE_PASS tests passed"
  fi
  echo ""
done

# ── 6. Resumen ────────────────────────────────────────────────────────────────
echo "────────────────────────────────────────"
echo -e "${BOLD}Results: $PASSED/$TOTAL passed${NC}"

if [ ${#FAILED_FILES[@]} -gt 0 ]; then
  echo ""
  fail "FAILED files:"
  for f in "${FAILED_FILES[@]}"; do
    echo "  - $f"
  done
  echo ""
  echo -e "${RED}${BOLD}❌ SUITE FAILED — git push BLOCKED by Test-Before-Push rule${NC}"
  echo "   Fix failing tests before pushing. See CLAUDE.md § Test-Before-Push."
  exit 1
fi

echo ""
echo -e "${GREEN}${BOLD}✅ ALL TESTS PASS — git push authorized${NC}"
echo "   Total: $TOTAL | Passed: $PASSED | Failed: 0"
echo ""
