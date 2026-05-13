#!/bin/bash
# log_append.sh — prepend atomic entry to docs/index.html log section
# Requiere que index.html tenga el anchor: <!-- LOG_INSERT -->
# Uso: bash log_append.sh "SUP-X" "descripción del cambio"

TAG="${1:-LOG}"
MSG="${2:-update}"
DATE=$(date +%Y-%m-%d)
INDEX="$(dirname "$0")/../../docs/index.html"

ENTRY="          <li class=\"log-item\">\n            <span class=\"log-tag tag-sup5\">${TAG}<\/span>\n            <span class=\"log-text\">${MSG}<\/span>\n            <span class=\"log-ts\">${DATE}<\/span>\n          <\/li>"

# Insertar DESPUÉS del anchor <!-- LOG_INSERT --> (prepend = más reciente primero)
sed -i "s|<!-- LOG_INSERT -->|<!-- LOG_INSERT -->\n${ENTRY}|" "$INDEX"

echo "[log_append] ${TAG} — ${MSG} (${DATE})"
