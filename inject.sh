#!/bin/bash
# inject.sh — Hydra Blueprint Injector
# Uso: bash inject.sh [--modules auth,users,billing,health-base,seed,rate-limit,audit,utils] [--reset]
# Clona blueprints seleccionados hacia active_project/

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
BLUEPRINTS="$REPO_ROOT/blueprints"
ACTIVE="$REPO_ROOT/active_project"
CONFIG="$ACTIVE/blueprints.json"

DEFAULT_MODULES="base,auth,users,billing,health-base,seed,rate-limit,audit,onboarding,notifications,utils"
MODULES="${DEFAULT_MODULES}"
RESET=false
NO_OAUTH=false
PROJECT_NAME=""

for arg in "$@"; do
  case "$arg" in
    --modules=*)  MODULES="${arg#--modules=}" ;;
    --reset)      RESET=true ;;
    --no-oauth)   NO_OAUTH=true ;;
    --project=*)  PROJECT_NAME="${arg#--project=}" ;;
    --help)
      echo "Uso: bash inject.sh [--modules=mod1,mod2,...] [--reset] [--no-oauth] [--project=NombreStartup]"
      echo "Módulos disponibles: base, auth, users, billing, health-base, seed, rate-limit, audit, onboarding, notifications, utils"
      echo "Flags:"
      echo "  --no-oauth    Excluye oauth.service.sql del módulo auth"
      echo "  --project=X   Nombre del proyecto activo (actualiza blueprints.json)"
      exit 0 ;;
  esac
done

echo "=== HYDRA INJECT ==="
echo "Módulos: $MODULES"
echo ""

if $RESET; then
  echo "→ Reset active_project/..."
  rm -rf "$ACTIVE/schemas" "$ACTIVE/services" "$ACTIVE/utils"
fi

mkdir -p "$ACTIVE/schemas" "$ACTIVE/services" "$ACTIVE/utils"

IFS=',' read -ra MOD_LIST <<< "$MODULES"
INJECTED=()

for mod in "${MOD_LIST[@]}"; do
  mod="$(echo "$mod" | tr -d ' ')"
  SRC="$BLUEPRINTS/$mod"

  if [ ! -d "$SRC" ]; then
    echo "  ⚠ Módulo '$mod' no encontrado en blueprints/ — ignorando"
    continue
  fi

  echo -n "  → Inyectando $mod ... "

  case "$mod" in
    base)
      cp "$SRC"/*.sql "$ACTIVE/schemas/" 2>/dev/null && echo "OK (schemas)" || echo "SKIP"
      ;;
    users)
      cp "$SRC"/*.sql "$ACTIVE/schemas/" 2>/dev/null && echo "OK (schemas)" || echo "SKIP"
      ;;
    billing)
      cp "$SRC"/[0-9]*.sql "$ACTIVE/schemas/" 2>/dev/null || true
      cp "$SRC"/billing.service.sql "$ACTIVE/services/" 2>/dev/null && echo "OK (schema+service)" || echo "SKIP"
      ;;
    auth)
      if $NO_OAUTH; then
        # Granular: excluir oauth.service.sql
        for f in auth.service.sql auth.flow.sql auth.context.sql; do
          cp "$SRC/$f" "$ACTIVE/services/" 2>/dev/null || true
        done
        echo "OK (services, sin OAuth)"
      else
        cp "$SRC"/*.sql "$ACTIVE/services/" 2>/dev/null && echo "OK (services, con OAuth)" || echo "SKIP"
      fi
      ;;
    health-base)
      cp "$SRC"/*.sql "$ACTIVE/schemas/" 2>/dev/null && echo "OK (schemas)" || echo "SKIP"
      ;;
    seed)
      cp "$SRC"/*.sql "$ACTIVE/schemas/" 2>/dev/null && echo "OK (schemas — dev only)" || echo "SKIP"
      ;;
    rate-limit)
      cp "$SRC"/*.sql "$ACTIVE/schemas/" 2>/dev/null && echo "OK (schemas)" || echo "SKIP"
      ;;
    audit)
      cp "$SRC"/*.sql "$ACTIVE/schemas/" 2>/dev/null && echo "OK (schemas)" || echo "SKIP"
      ;;
    onboarding)
      cp "$SRC"/*.sql "$ACTIVE/schemas/" 2>/dev/null && echo "OK (schemas)" || echo "SKIP"
      ;;
    notifications)
      cp "$SRC"/*.sql "$ACTIVE/schemas/" 2>/dev/null && echo "OK (schemas)" || echo "SKIP"
      ;;
    utils)
      cp "$SRC"/*.sql "$ACTIVE/utils/" 2>/dev/null && echo "OK (utils)" || echo "SKIP"
      ;;
    *)
      cp "$SRC"/*.sql "$ACTIVE/schemas/" 2>/dev/null && echo "OK" || echo "SKIP"
      ;;
  esac

  INJECTED+=("$mod")
done

# Resolver nombre del proyecto: --project flag > existente en blueprints.json > default
if [[ -n "$PROJECT_NAME" ]]; then
  PROJ_NAME="$PROJECT_NAME"
else
  PROJ_NAME=$([ -f "$CONFIG" ] && jq -r '.project // "Hydra Project"' "$CONFIG" 2>/dev/null || echo "Hydra Project")
fi

cat > "$CONFIG" <<EOF
{
  "project": "${PROJ_NAME}",
  "injected_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "modules": [$(printf '"%s",' "${INJECTED[@]}" | sed 's/,$//')]
}
EOF

echo ""
echo "=== Inyección completa ==="
echo "Proyecto:  ${PROJ_NAME}"
echo "Módulos:   ${INJECTED[*]}"
echo "OAuth:     $( $NO_OAUTH && echo 'NO (--no-oauth)' || echo 'SÍ')"
echo ""
echo "Siguiente: export DATABASE_URL=... && bash core/migrations/runner.sh"
