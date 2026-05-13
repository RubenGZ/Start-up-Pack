#!/bin/bash
# log_append.sh — append atomic entry to docs/index.html
MSG="${1:-update}"
DATE=$(date +%Y-%m-%d)
ENTRY="  <li><span class=\"ts\">${DATE}</span> ${MSG}</li>"
sed -i "s|</ul>|${ENTRY}\n</ul>|" "$(dirname "$0")/../../docs/index.html"
