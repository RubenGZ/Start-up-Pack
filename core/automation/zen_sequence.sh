#!/bin/bash
# zen_sequence.sh — post-success: log + git push + slack notify
MSG="${1:-update}"
CONFIG="$(dirname "$0")/config.json"
SLACK_TOKEN=$(jq -r '.slack_token' "$CONFIG")
SLACK_CHANNEL=$(jq -r '.slack_channel' "$CONFIG")
ROOT="$(dirname "$0")/../.."

# 1. Log atómico
bash "$(dirname "$0")/log_append.sh" "$MSG"

# 2. Git
cd "$ROOT" && git add . && git commit -m "$MSG" && git push

# 3. Slack
curl -s -X POST https://slack.com/api/chat.postMessage \
  -H "Authorization: Bearer $SLACK_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"channel\":\"$SLACK_CHANNEL\",\"text\":\"[DONE] $MSG\"}" > /dev/null
