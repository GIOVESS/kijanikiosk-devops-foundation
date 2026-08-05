#!/bin/bash
set -euo pipefail

TARGET="${1:-}"
ACTIVE_ENV_FILE=/opt/kijanikiosk/.active-env
PREVIOUS_ENV_FILE=/opt/kijanikiosk/.previous-env
NGINX_CONF=/etc/nginx/kijanikiosk-active-env.conf

if [[ "$TARGET" != "blue" && "$TARGET" != "green" ]]; then
  echo "Usage: switch-env.sh <blue|green>" >&2
  exit 1
fi

if [[ "$TARGET" == "blue" ]]; then
  PORT=3000
else
  PORT=3001
fi

CURRENT=$(cat "$ACTIVE_ENV_FILE" 2>/dev/null || echo none)

echo "[$(date -u +%H:%M:%S)] Switching from $CURRENT to $TARGET (port $PORT)"

cat <<CONF | sudo tee "$NGINX_CONF" > /dev/null
# Managed by switch-env.sh - do not edit manually
upstream kijanikiosk_active {
    server 127.0.0.1:$PORT; # kk-api-$TARGET
}
CONF

nginx -t
systemctl reload nginx

echo "$CURRENT" | sudo tee "$PREVIOUS_ENV_FILE" > /dev/null
echo "$TARGET" | sudo tee "$ACTIVE_ENV_FILE" > /dev/null

sleep 1
RESULT=$(curl -s http://127.0.0.1:80/health)
echo "[$(date -u +%H:%M:%S)] Post-switch health: $RESULT"
