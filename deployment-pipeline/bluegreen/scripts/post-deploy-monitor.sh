#!/bin/bash
set -uo pipefail

CONFIDENCE_WINDOW="${1:-60}"
POLL_INTERVAL=5
FAILURE_THRESHOLD=2

ACTIVE_ENV_FILE=/opt/kijanikiosk/.active-env
SCRIPT_DIR=/opt/kijanikiosk/scripts

ACTIVE=$(cat "$ACTIVE_ENV_FILE")
if [[ "$ACTIVE" == "blue" ]]; then
  ACTIVE_PORT=3000
  ROLLBACK_TARGET=green
else
  ACTIVE_PORT=3001
  ROLLBACK_TARGET=blue
fi

fail_count=0
elapsed=0

echo "[$(date -u +%H:%M:%S)] Monitor started. Watching $ACTIVE (port $ACTIVE_PORT). Confidence window: ${CONFIDENCE_WINDOW}s. Poll interval: ${POLL_INTERVAL}s."

while (( elapsed < CONFIDENCE_WINDOW )); do
  if curl -sf --max-time 3 "http://127.0.0.1:${ACTIVE_PORT}/health" > /dev/null; then
    if (( fail_count > 0 )); then
      echo "[$(date -u +%H:%M:%S)] Health check recovered."
    fi
    fail_count=0
  else
    fail_count=$((fail_count+1))
    echo "[$(date -u +%H:%M:%S)] Health check failed (consecutive: $fail_count)"
    if (( fail_count >= FAILURE_THRESHOLD )); then
      echo "[$(date -u +%H:%M:%S)] [MONITOR FAIL] ROLLBACK TRIGGERED - rolling back to $ROLLBACK_TARGET"
      bash "$SCRIPT_DIR/switch-env.sh" "$ROLLBACK_TARGET"
      echo "[$(date -u +%H:%M:%S)] Rollback complete. Verifying..."
      curl -s http://127.0.0.1:80/health
      exit 0
    fi
  fi
  sleep "$POLL_INTERVAL"
  elapsed=$((elapsed+POLL_INTERVAL))
done

echo "[$(date -u +%H:%M:%S)] Confidence window elapsed with no rollback triggered. Deployment considered stable."
