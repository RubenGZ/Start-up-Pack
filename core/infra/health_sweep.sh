#!/bin/bash
# health_sweep.sh — detecta archivos pesados y logs que ensucian el contexto

THRESHOLD=250
ROOT="${1:-.}"
ISSUES=0

echo "=== HEALTH SWEEP ==="

# Archivos con más de $THRESHOLD líneas (incluye .sql)
echo "--- Archivos >$THRESHOLD líneas ---"
while IFS= read -r -d '' file; do
  lines=$(wc -l < "$file")
  if [ "$lines" -gt "$THRESHOLD" ]; then
    echo "  [$lines L] $file → MODULARIZAR"
    ((ISSUES++))
  fi
done < <(find "$ROOT" -type f \( \
  -name "*.js" -o -name "*.ts" -o -name "*.py" \
  -o -name "*.sh" -o -name "*.md" -o -name "*.sql" \
  \) ! -path "*/.git/*" ! -path "*/node_modules/*" -print0)

# Logs pesados (>1MB)
echo "--- Logs pesados (>1MB) ---"
while IFS= read -r -d '' file; do
  size=$(du -k "$file" | cut -f1)
  if [ "$size" -gt 1024 ]; then
    echo "  [${size}KB] $file → LIMPIAR"
    ((ISSUES++))
  fi
done < <(find "$ROOT" -type f -name "*.log" ! -path "*/.git/*" -print0)

echo "=== TOTAL ISSUES: $ISSUES ==="
exit $ISSUES
