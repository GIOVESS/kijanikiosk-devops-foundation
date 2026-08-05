#!/usr/bin/env bash
# scripts/deploy-app.sh
# Deploys a versioned kk-api artifact to the blue or green environment.
#
# Required:
#   APP_VERSION       e.g. "v1.4.0"
#   DEPLOY_ENV        "blue" or "green"
#   ARTIFACT_BASE_URL Base URL for artifact downloads
# Optional:
#   BLUE_PORT   (default: 3000)
#   GREEN_PORT  (default: 3001)
#
# Deviation from brief: writes APP_VERSION/PORT into a per-environment
# EnvironmentFile (kk-api-<env>.env) so systemd doesn't hardcode a stale
# version across redeploys. The brief's unit files as written would report
# the wrong version after the second deploy to the same environment.

set -euo pipefail

APP_VERSION="${APP_VERSION:?APP_VERSION environment variable is required}"
DEPLOY_ENV="${DEPLOY_ENV:?DEPLOY_ENV must be 'blue' or 'green'}"
ARTIFACT_BASE_URL="${ARTIFACT_BASE_URL:?ARTIFACT_BASE_URL is required}"
BLUE_PORT="${BLUE_PORT:-3000}"
GREEN_PORT="${GREEN_PORT:-3001}"

case "${DEPLOY_ENV}" in
  blue|green) ;;
  *) echo "ERROR: DEPLOY_ENV must be 'blue' or 'green', got '${DEPLOY_ENV}'"; exit 1 ;;
esac

SCRIPT_START=$(date +%s)
log() {
  local elapsed=$(( $(date +%s) - SCRIPT_START ))
  echo "[$(date -u +%H:%M:%S)] [+${elapsed}s] $*"
}
log_fail() {
  echo "[$(date -u +%H:%M:%S)] [FAIL] $*" >&2
}

# ── Phase 1: Fetch ────────────────────────────────────────────────────────
fetch_artifact() {
  log "=== Phase 1: Fetch artifact ==="
  local artifact_url="${ARTIFACT_BASE_URL}/kk-api-${APP_VERSION}.tar.gz"
  local dest="/opt/kijanikiosk/releases/kk-api-${APP_VERSION}.tar.gz"

  if [ -f "${dest}" ]; then
    log "Artifact already downloaded: ${dest}"
    return 0
  fi

  mkdir -p /opt/kijanikiosk/releases
  curl -fsSL --max-time 60 "${artifact_url}" -o "${dest}" || {
    log_fail "Phase 1 FAILED: Could not fetch ${artifact_url}"
    exit 1
  }
  log "Fetched: ${dest}"
}

# ── Phase 2: Validate ─────────────────────────────────────────────────────
validate_artifact() {
  log "=== Phase 2: Validate artifact ==="
  local dest="/opt/kijanikiosk/releases/kk-api-${APP_VERSION}.tar.gz"

  [ -s "${dest}" ] || { log_fail "Phase 2 FAILED: Artifact file is missing or empty"; exit 1; }

  if [ -f "${dest}.sha256" ]; then
    (cd /opt/kijanikiosk/releases && sha256sum -c "$(basename "${dest}").sha256") || {
      log_fail "Phase 2 FAILED: Checksum mismatch on ${dest}"
      exit 1
    }
  fi

  local staging="/opt/kijanikiosk/releases/staging-${APP_VERSION}"
  rm -rf "${staging}"
  mkdir -p "${staging}"
  tar xzf "${dest}" -C "${staging}" --strip-components=1 || {
    log_fail "Phase 2 FAILED: Could not extract artifact"
    exit 1
  }
  [ -f "${staging}/server.js" ] || {
    log_fail "Phase 2 FAILED: server.js not found in artifact"
    exit 1
  }
  log "Artifact valid: server.js present, extraction successful"
}

# ── Phase 3: Deploy ────────────────────────────────────────────────────────
deploy_artifact() {
  log "=== Phase 3: Deploy to ${DEPLOY_ENV} environment ==="
  local target_dir="/opt/kijanikiosk/${DEPLOY_ENV}"
  local staging="/opt/kijanikiosk/releases/staging-${APP_VERSION}"
  local current_version_file="${target_dir}/.version"
  local port
  [ "${DEPLOY_ENV}" = "blue" ] && port="${BLUE_PORT}" || port="${GREEN_PORT}"
  local env_file="/opt/kijanikiosk/config/kk-api-${DEPLOY_ENV}.env"

  # Always write the env file: even on an idempotent skip, restart_service
  # must see the correct APP_VERSION/PORT for this environment.
  mkdir -p /opt/kijanikiosk/config
  cat > "${env_file}" << ENVEOF
APP_VERSION=${APP_VERSION}
PORT=${port}
NODE_ENV=staging
ENVEOF
  chown root:kijanikiosk "${env_file}"
  chmod 0640 "${env_file}"

  if [ -f "${current_version_file}" ] && [ "$(cat "${current_version_file}")" = "${APP_VERSION}" ]; then
    log "Version ${APP_VERSION} already deployed to ${DEPLOY_ENV}. Skipping copy."
    return 0
  fi

  mkdir -p "${target_dir}"
  chown kk-api:kk-api "${target_dir}"

  cp -r "${staging}/." "${target_dir}/new_version/"
  mv "${target_dir}/new_version" "${target_dir}/app"
  chown -R kk-api:kk-api "${target_dir}/app"

  echo "${APP_VERSION}" > "${current_version_file}"
  log "Deployed version ${APP_VERSION} to ${target_dir}"
}

# ── Phase 4: Restart ───────────────────────────────────────────────────────
restart_service() {
  log "=== Phase 4: Restart ${DEPLOY_ENV} service ==="
  local service_name="kk-api-${DEPLOY_ENV}.service"

  systemctl daemon-reload
  systemctl restart "${service_name}" || {
    log_fail "Phase 4 FAILED: Could not restart ${service_name}"
    journalctl -u "${service_name}" --since "1 minute ago" --no-pager | tail -20
    exit 1
  }

  local retries=0
  while [ ${retries} -lt 30 ]; do
    if systemctl is-active --quiet "${service_name}"; then
      log "Service ${service_name} is active"
      return 0
    fi
    sleep 1
    retries=$((retries + 1))
  done

  log_fail "Phase 4 FAILED: ${service_name} did not become active within 30 seconds"
  journalctl -u "${service_name}" --since "1 minute ago" --no-pager | tail -20
  exit 1
}

# ── Phase 5: Verify ────────────────────────────────────────────────────────
verify_service() {
  log "=== Phase 5: Verify ${DEPLOY_ENV} service health ==="
  local port
  [ "${DEPLOY_ENV}" = "blue" ] && port="${BLUE_PORT}" || port="${GREEN_PORT}"
  local health_url="http://127.0.0.1:${port}/health"
  local retries=0

  while [ ${retries} -lt 10 ]; do
    response=$(curl -sf --max-time 5 "${health_url}" 2>/dev/null) && {
      echo "${response}" | grep -q "\"version\":\"${APP_VERSION}\"" && {
        log "Health check passed: ${health_url} returned version ${APP_VERSION}"
        return 0
      }
      log "Health check responded but version mismatch: ${response}"
    }
    sleep 3
    retries=$((retries + 1))
  done

  log_fail "Phase 5 FAILED: Health check did not pass after $((retries * 3)) seconds"
  log_fail "URL: ${health_url}"
  exit 1
}

main() {
  log "=== kk-api Deployment Script ==="
  log "Version: ${APP_VERSION}"
  log "Target: ${DEPLOY_ENV}"
  log "Artifact: ${ARTIFACT_BASE_URL}/kk-api-${APP_VERSION}.tar.gz"
  echo ""

  fetch_artifact
  validate_artifact
  deploy_artifact
  restart_service
  verify_service

  echo ""
  log "=== Deployment complete: kk-api ${APP_VERSION} on ${DEPLOY_ENV} ==="
  exit 0
}

main "$@"
