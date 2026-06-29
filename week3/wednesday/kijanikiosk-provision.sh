#!/usr/bin/env bash
# =============================================================================
# KijaniKiosk Wednesday Provisioning Script
# Lab: Hardened Service Deployment
# Target: Ubuntu 22.04 LTS
# Run as: sudo bash kijanikiosk-provision.sh
# Idempotent: yes
# =============================================================================

set -euo pipefail

if ! grep -qi ubuntu /etc/os-release 2>/dev/null; then
  echo "[FAIL] This script requires Ubuntu."
  exit 1
fi

log()     { echo "[$(date -Is)] [INFO]  $*"; }
success() { echo "[$(date -Is)] [PASS]  $*"; }
warn()    { echo "[$(date -Is)] [WARN]  $*"; }
error()   { echo "[$(date -Is)] [FAIL]  $*" >&2; }
phase()   {
  printf "\n%s\n[PHASE %s] %s\n%s\n" \
    "========================================" "$1" "$2" \
    "========================================"
}

FAILED_CHECKS=()
record_check() {
  local label="$1" result="$2"
  if [[ "$result" == "pass" ]]; then
    success "PASS: $label"
  else
    error "FAIL: $label"
    FAILED_CHECKS+=("$label")
  fi
}

if [[ $EUID -ne 0 ]]; then
  error "Must run as root: sudo $0"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
phase 1 "SERVICE ACCOUNTS"
# ─────────────────────────────────────────────────────────────────────────────

if ! getent group kijanikiosk &>/dev/null; then
  groupadd --system kijanikiosk
  log "Created group: kijanikiosk"
else
  log "Already exists: group kijanikiosk — skipping"
fi

for svc in kk-api kk-payments kk-logs; do
  if ! id "$svc" &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin \
      --comment "KijaniKiosk ${svc} service account" "$svc"
    log "Created: $svc (UID $(id -u $svc))"
  else
    log "Already exists: $svc (UID $(id -u $svc)) — skipping"
  fi
  if ! id -nG "$svc" | grep -qw kijanikiosk; then
    usermod -aG kijanikiosk "$svc"
    log "Added $svc to kijanikiosk group"
  else
    log "$svc already in kijanikiosk group — skipping"
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
phase 2 "DIRECTORY STRUCTURE AND ACLs"
# ─────────────────────────────────────────────────────────────────────────────

mkdir -p /opt/kijanikiosk/{api,payments,logs,config,scripts,shared/logs}

chown kk-api:kk-api           /opt/kijanikiosk/api/          && chmod 750 /opt/kijanikiosk/api/
chown kk-payments:kk-payments /opt/kijanikiosk/payments/     && chmod 750 /opt/kijanikiosk/payments/
chown kk-logs:kk-logs         /opt/kijanikiosk/logs/         && chmod 750 /opt/kijanikiosk/logs/
chown root:kijanikiosk        /opt/kijanikiosk/config/       && chmod 750 /opt/kijanikiosk/config/
chown kk-logs:kijanikiosk     /opt/kijanikiosk/shared/logs/  && chmod 2770 /opt/kijanikiosk/shared/logs/

setfacl -m u:kk-api:rwx,u:kk-payments:r-x,u:kk-logs:rwx \
  /opt/kijanikiosk/shared/logs/
setfacl -d -m u:kk-api:rwx,u:kk-payments:r-x,u:kk-logs:rwx \
  /opt/kijanikiosk/shared/logs/

log "Directory structure and ACLs applied"

for f in api.env payments-api.env logs.env; do
  [[ -f /opt/kijanikiosk/config/$f ]] || { touch /opt/kijanikiosk/config/$f; log "Created: $f"; }
done
chown kk-api:kijanikiosk      /opt/kijanikiosk/config/api.env          && chmod 640 /opt/kijanikiosk/config/api.env
chown kk-payments:kijanikiosk /opt/kijanikiosk/config/payments-api.env && chmod 640 /opt/kijanikiosk/config/payments-api.env
chown kk-logs:kijanikiosk     /opt/kijanikiosk/config/logs.env         && chmod 640 /opt/kijanikiosk/config/logs.env

# ─────────────────────────────────────────────────────────────────────────────
phase 3 "PACKAGE INSTALLATION AND PINNING"
# ─────────────────────────────────────────────────────────────────────────────

apt-get update -qq

if apt-mark showhold | grep -q nginx; then
  apt-mark unhold nginx && log "Removed nginx hold"
fi
NGINX_INSTALLED=$(dpkg-query -W -f='${Version}' nginx 2>/dev/null || echo "none")
NGINX_CANDIDATE=$(apt-cache policy nginx 2>/dev/null | grep Candidate | awk '{print $2}')
if [[ "$NGINX_INSTALLED" == "none" ]]; then
  apt-get install -y nginx && log "Installed nginx"
elif [[ "$NGINX_INSTALLED" == "$NGINX_CANDIDATE" ]]; then
  log "nginx already at $NGINX_INSTALLED — skipping"
fi
apt-mark hold nginx
log "nginx held at: $(dpkg-query -W -f='${Version}' nginx)"

if apt-mark showhold | grep -q nodejs; then
  apt-mark unhold nodejs && log "Removed nodejs hold"
fi
if ! dpkg -l nodejs &>/dev/null; then
  apt-get install -y nodejs && log "Installed nodejs"
else
  log "nodejs already installed — skipping"
fi
apt-mark hold nodejs
log "nodejs held at: $(dpkg-query -W -f='${Version}' nodejs)"

# ─────────────────────────────────────────────────────────────────────────────
phase 4 "SYSTEMD UNIT FILE — kk-api"
# ─────────────────────────────────────────────────────────────────────────────
# ExecStart uses /bin/sleep infinity as placeholder — no app code deployed yet.
# Unit is enabled for boot but intentionally not started here.
# Hardening directives target score < 4.0. Two directives added beyond Page 3
# baseline: SystemCallFilter=@system-service and RestrictNamespaces=yes.
# See security-analysis.md for rationale and score progression.

cat > /etc/systemd/system/kk-api.service << 'UNIT'
[Unit]
Description=KijaniKiosk API Service
Documentation=https://github.com/GIOVESS/kijanikiosk-devops-foundation
After=network.target

[Service]
Type=simple
User=kk-api
Group=kijanikiosk
EnvironmentFile=/opt/kijanikiosk/config/api.env
ExecStart=/bin/sleep infinity
Restart=on-failure
RestartSec=5s
StartLimitIntervalSec=60s
StartLimitBurst=3
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kk-api

# Baseline hardening (Page 3 directives)
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
ReadWritePaths=/opt/kijanikiosk/shared/logs
CapabilityBoundingSet=
AmbientCapabilities=

# Additional hardening (two directives added beyond baseline — see security-analysis.md)
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
LockPersonality=yes
MemoryDenyWriteExecute=yes
RestrictNamespaces=yes
SystemCallFilter=@system-service
SystemCallArchitectures=native
RestrictSUIDSGID=yes
RestrictRealtime=yes
ProtectClock=yes
ProtectHostname=yes
UMask=0027

[Install]
WantedBy=multi-user.target
UNIT

log "Written: /etc/systemd/system/kk-api.service"
systemctl daemon-reload
systemctl enable kk-api.service
log "Enabled kk-api.service (not started — no app code deployed)"

# ─────────────────────────────────────────────────────────────────────────────
phase 5 "FIREWALL"
# ─────────────────────────────────────────────────────────────────────────────

command -v ufw &>/dev/null || apt-get install -y ufw

ufw --force reset
ufw --force disable
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment "SSH: remote administration"
ufw allow 80/tcp comment "HTTP: nginx ingress"
ufw --force enable
log "Firewall enabled: SSH (22) and HTTP (80) allowed, all else denied"

# ─────────────────────────────────────────────────────────────────────────────
phase 6 "VERIFICATION"
# ─────────────────────────────────────────────────────────────────────────────

FAILED_CHECKS=()

for u in kk-api kk-payments kk-logs; do
  id "$u" &>/dev/null \
    && record_check "$u exists" pass \
    || record_check "$u exists" fail
  id -nG "$u" | grep -qw kijanikiosk \
    && record_check "$u in kijanikiosk group" pass \
    || record_check "$u in kijanikiosk group" fail
done

[[ $(stat -c '%a' /opt/kijanikiosk/config) == "750" ]] \
  && record_check "config dir mode 750" pass \
  || record_check "config dir mode 750" fail

# setgid bit makes stat report 3770 — both 2770 and 3770 are correct
LOGS_MODE=$(stat -c '%a' /opt/kijanikiosk/shared/logs)
[[ "$LOGS_MODE" == "3770" || "$LOGS_MODE" == "2770" ]] \
  && record_check "shared/logs setgid mode ($LOGS_MODE)" pass \
  || record_check "shared/logs setgid mode ($LOGS_MODE)" fail

getfacl /opt/kijanikiosk/shared/logs 2>/dev/null | grep -q "user:kk-api:rwx" \
  && record_check "shared/logs ACL kk-api:rwx" pass \
  || record_check "shared/logs ACL kk-api:rwx" fail

dpkg -l nginx 2>/dev/null | grep -q "^hi" \
  && record_check "nginx held" pass \
  || record_check "nginx held" fail

apt-mark showhold | grep -q nodejs \
  && record_check "nodejs held" pass \
  || record_check "nodejs held" fail

systemctl is-enabled kk-api.service 2>/dev/null | grep -q enabled \
  && record_check "kk-api.service enabled" pass \
  || record_check "kk-api.service enabled" fail

SCORE=$(systemd-analyze security kk-api.service 2>/dev/null \
  | tail -1 | grep -oP '\d+\.\d+' || echo "99")
awk "BEGIN{exit ($SCORE < 4.0) ? 0 : 1}" \
  && record_check "kk-api hardening score < 4.0 ($SCORE)" pass \
  || record_check "kk-api hardening score < 4.0 ($SCORE)" fail

UFW_OUT=$(ufw status)
echo "$UFW_OUT" | grep -q "22/tcp.*ALLOW" \
  && record_check "ufw SSH allowed" pass \
  || record_check "ufw SSH allowed" fail
echo "$UFW_OUT" | grep -q "80/tcp.*ALLOW" \
  && record_check "ufw HTTP allowed" pass \
  || record_check "ufw HTTP allowed" fail

echo ""
echo "========================================"
TOTAL=${#FAILED_CHECKS[@]}
if [[ $TOTAL -eq 0 ]]; then
  success "All checks passed. Exit 0."
  echo "========================================"
  exit 0
else
  error "$TOTAL check(s) failed:"
  for c in "${FAILED_CHECKS[@]}"; do error "  ✗ $c"; done
  echo "========================================"
  exit 1
fi
