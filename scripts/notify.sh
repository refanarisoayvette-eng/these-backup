#!/bin/bash
STATUS="${1:-INFO}"
MESSAGE="${2:-Notification}"
WEBHOOK_URL="${DISCORD_WEBHOOK:-}"

if [ -z "$WEBHOOK_URL" ]; then
    echo "[notify] Pas de DISCORD_WEBHOOK, skip"
    exit 0
fi

case "$STATUS" in
    SUCCESS) COLOR=3066993 ; EMOJI="✅" ; TITLE="Backup PostgreSQL - Succes" ;;
    FAILURE) COLOR=15158332 ; EMOJI="❌" ; TITLE="Backup PostgreSQL - ECHEC" ;;
    WARNING) COLOR=15105570 ; EMOJI="⚠️" ; TITLE="Backup PostgreSQL - Avertissement" ;;
    *) COLOR=3447003 ; EMOJI="ℹ️" ; TITLE="Backup PostgreSQL - Info" ;;
esac

HOSTNAME=$(hostname)

PAYLOAD=$(cat << JSON
{
  "embeds": [{
    "title": "$EMOJI $TITLE",
    "description": "$MESSAGE",
    "color": $COLOR,
    "footer": { "text": "Serveur: $HOSTNAME - $(date '+%Y-%m-%d %H:%M:%S')" }
  }]
}
JSON
)

curl -s -H "Content-Type: application/json" -d "$PAYLOAD" "$WEBHOOK_URL" > /dev/null 2>&1
