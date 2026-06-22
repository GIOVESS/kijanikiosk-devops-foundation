#!/usr/bin/env bash
# =============================================================================
# KijaniKiosk Production Server Provisioning Script
# Target:      Ubuntu 22.04 LTS (Jammy)
# Run as:      sudo ./kijanikiosk-provision.sh
# Idempotent:  Yes — safe to run on dirty or clean state
# =============================================================================
#
# Expected dirty conditions found in pre-provisioning audit (2026-06-22):
# - kk-api absent: UID 998 conflict with existing system account;
#   handled in Phase 2 by id check then useradd without forced UID
# - kk-payments exists (UID 997): not in kijanikiosk group; fixed Phase 2
# - kk-logs exists (UID 996): not in kijanikiosk group; fixed Phase 2
# - kijanikiosk group exists (GID 1002) but empty; populated Phase 2
# - /opt/kijanikiosk/config is 777; corrected to 750 in Phase 3
# - /opt/kijanikiosk/shared/logs has no extended ACLs; applied Phase 3
# - ufw has spurious deny 3001 rule from Thursday; reset in Phase 5
# - nginx package hold set manually; unhold->install->re-hold in Phase 4
# - kk-api.service exists unhardened (score ~9.6); overwritten Phase 6
# =============================================================================

set -uo pipefail

# ─── Logging helpers ──────────────────────────────────────────────────────────
log()     { echo "[$(date -Is)] [INFO]  $*"; }
success() { echo "[$(date -Is)] [PASS]  $*"; }
warn()    { echo "[$(date -Is)] [WARN]  $*"; }
error()   { echo "[$(date -Is)] [FAIL]  $*" >&2; }
phase()   {
  printf "\n%s\n[PHASE %s] %s\n%s\n" \
    "================================================" \
    "$1" "$2" \
    "================================================"
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
phase 1 "PRE-FLIGHT: Dirty State Detection"
# ─────────────────────────────────────────────────────────────────────────────

log "Auditing existing state before convergence..."

if id kk-api &>/dev/null; then
  warn "Already exists: kk-api (UID $(id -u kk-api)) — will verify group membership"
else
  warn "Missing: kk-api — UID 998 conflict detected; will create without forced UID"
fi

if id kk-payments &>/dev/null; then
  warn "Already exists: kk-payments (UID $(id -u kk-payments)) — will verify group membership"
fi

if id kk-logs &>/dev/null; then
  warn "Already exists: kk-logs (UID $(id -u kk-logs)) — will verify group membership"
fi

if getent group kijanikiosk &>/dev/null; then
  warn "Already exists: group kijanikiosk (GID $(getent group kijanikiosk | cut -d: -f3))"
fi

CONFIG_PERMS=$(stat -c '%a' /opt/kijanikiosk/config 2>/dev/null || echo "missing")
if [[ "$CONFIG_PERMS" == "777" ]]; then
  warn "Dirty: /opt/kijanikiosk/config is 777 — will correct to 750 in Phase 3"
fi

UFW_SPURIOUS=$(ufw status numbered 2>/dev/null | grep -c "3001.*DENY" || true)
if [[ "$UFW_SPURIOUS" -gt 0 ]]; then
  warn "Dirty: spurious ufw DENY 3001 rule detected — full reset in Phase 5"
fi

NGINX_HOLD=$(apt-mark showhold 2>/dev/null | grep -c nginx || true)
if [[ "$NGINX_HOLD" -gt 0 ]]; then
  warn "Dirty: nginx package hold present — unhold before install, re-hold after"
fi

if [[ -f /etc/systemd/system/kk-api.service ]]; then
  warn "Dirty: kk-api.service exists — will overwrite with hardened version in Phase 6"
fi

log "Pre-flight complete. Beginning convergence."

# ─────────────────────────────────────────────────────────────────────────────
phase 2 "SERVICE ACCOUNTS"
# ─────────────────────────────────────────────────────────────────────────────

if ! getent group kijanikiosk &>/dev/null; then
  groupadd --system kijanikiosk
  log "Created group: kijanikiosk"
else
  log "Already exists: group kijanikiosk (GID $(getent group kijanikiosk | cut -d: -f3)) — skipping creation"
fi

if ! id kk-api &>/dev/null; then
  useradd --system --no-create-home --shell /usr/sbin/nologin \
    --comment "KijaniKiosk API service account" kk-api
  log "Created kk-api (UID assigned: $(id -u kk-api))"
else
  log "Already exists: kk-api (UID $(id -u kk-api)) — skipping creation"
fi

if ! id kk-payments &>/dev/null; then
  useradd --system --no-create-home --shell /usr/sbin/nologin \
    --comment "KijaniKiosk Payments service account" kk-payments
  log "Created kk-payments (UID $(id -u kk-payments))"
else
  log "Already exists: kk-payments (UID $(id -u kk-payments)) — skipping creation"
fi

if ! id kk-logs &>/dev/null; then
  useradd --system --no-create-home --shell /usr/sbin/nologin \
    --comment "KijaniKiosk Log aggregation service account" kk-logs
  log "Created kk-logs (UID $(id -u kk-logs))"
else
  log "Already exists: kk-logs (UID $(id -u kk-logs)) — skipping creation"
fi

for svc_user in kk-api kk-payments kk-logs; do
  if id "$svc_user" &>/dev/null; then
    if id -nG "$svc_user" | grep -qw kijanikiosk; then
      log "$svc_user already in kijanikiosk group — skipping"
    else
      usermod -aG kijanikiosk "$svc_user"
      log "Added $svc_user to kijanikiosk group"
    fi
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
phase 3 "DIRECTORY STRUCTURE AND ACCESS CONTROL LISTS"
# ─────────────────────────────────────────────────────────────────────────────

mkdir -p \
  /opt/kijanikiosk/shared/logs \
  /opt/kijanikiosk/config \
  /opt/kijanikiosk/health

chown root:kijanikiosk /opt/kijanikiosk
chmod 750 /opt/kijanikiosk

chown root:kijanikiosk /opt/kijanikiosk/config
chmod 750 /opt/kijanikiosk/config
log "Set /opt/kijanikiosk/config: root:kijanikiosk 750 (was 777)"

chown kk-api:kijanikiosk /opt/kijanikiosk/shared/logs
chmod 2750 /opt/kijanikiosk/shared/logs

setfacl -m u:kk-api:rwx,u:kk-payments:r-x,u:kk-logs:rwx \
  /opt/kijanikiosk/shared/logs
setfacl -d -m u:kk-api:rwx,u:kk-payments:r-x,u:kk-logs:rwx \
  /opt/kijanikiosk/shared/logs
log "Applied extended and default ACLs to /opt/kijanikiosk/shared/logs"

chown root:kijanikiosk /opt/kijanikiosk/health
chmod 750 /opt/kijanikiosk/health
log "Set /opt/kijanikiosk/health: root:kijanikiosk 750"

create_env_file() {
  local path="$1" owner="$2"
  if [[ ! -f "$path" ]]; then
    touch "$path"
    log "Created env file: $path"
  else
    log "Already exists: $path — verifying ownership and permissions"
  fi
  chown "${owner}:kijanikiosk" "$path"
  chmod 640 "$path"
}

create_env_file /opt/kijanikiosk/config/api.env          kk-api
create_env_file /opt/kijanikiosk/config/payments-api.env kk-payments
create_env_file /opt/kijanikiosk/config/logs.env         kk-logs

# Integration Challenge A: verify EnvironmentFile readable before Phase 6
# ProtectSystem=strict makes /etc read-only — /opt is unaffected
if sudo -u kk-payments test -r /opt/kijanikiosk/config/payments-api.env; then
  log "Verified: kk-payments can read payments-api.env"
else
  error "kk-payments cannot read payments-api.env — aborting to prevent Phase 6 failure"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
phase 4 "PACKAGE PINNING"
# ─────────────────────────────────────────────────────────────────────────────

# Integration Challenge D: unhold before any apt operation
if apt-mark showhold | grep -q nginx; then
  apt-mark unhold nginx
  log "Removed nginx hold before install check"
fi

INSTALLED=$(dpkg-query -W -f='${Version}' nginx 2>/dev/null || echo "none")
CANDIDATE=$(apt-cache policy nginx 2>/dev/null | grep Candidate | awk '{print $2}')

log "nginx installed: $INSTALLED | candidate: $CANDIDATE"

if [[ "$INSTALLED" == "none" ]]; then
  apt-get install -y nginx
  log "Installed nginx ($(dpkg-query -W -f='${Version}' nginx))"
elif [[ "$INSTALLED" == "$CANDIDATE" ]]; then
  log "nginx already at candidate version $INSTALLED — skipping install"
else
  warn "nginx version mismatch ($INSTALLED vs $CANDIDATE) — installing candidate"
  apt-get install -y nginx
fi

apt-mark hold nginx
log "nginx held at: $(dpkg-query -W -f='${Version}' nginx)"

# ─────────────────────────────────────────────────────────────────────────────
phase 5 "FIREWALL: Intent-Based Ruleset"
# ─────────────────────────────────────────────────────────────────────────────

log "Resetting ufw to clean baseline (discards all manual edits and Thursday rules)..."
ufw --force reset
ufw --force disable

ufw default deny incoming
ufw default allow outgoing

# Rules added in order: allow rules for 3001 MUST precede the deny rule
# (ufw first-match wins — out-of-order = loopback traffic blocked by deny)
ufw allow 22/tcp comment "SSH: remote administration"
ufw allow 80/tcp comment "HTTP: nginx ingress for kk-api reverse proxy"
ufw allow in on lo to any port 3000 \
  comment "kk-api: loopback only, nginx proxy target"
ufw allow in on lo to any port 3001 \
  comment "kk-payments: loopback only, nginx proxy target"
ufw allow from 10.0.1.0/24 to any port 3001 \
  comment "kk-payments: health endpoint, monitoring subnet only"
ufw deny 3001 \
  comment "kk-payments: block all external access (internal service port)"

ufw --force enable
log "Firewall enabled with intent-based ruleset"

FIREWALL_FAILED=0
UFW_STATUS=$(ufw status)

echo "$UFW_STATUS" | grep -q "22/tcp.*ALLOW" \
  && success "PASS: SSH (22) allowed" \
  || { error "FAIL: SSH (22) rule missing"; FIREWALL_FAILED=$((FIREWALL_FAILED + 1)); }

echo "$UFW_STATUS" | grep -q "80/tcp.*ALLOW" \
  && success "PASS: HTTP (80) allowed" \
  || { error "FAIL: HTTP (80) rule missing"; FIREWALL_FAILED=$((FIREWALL_FAILED + 1)); }

echo "$UFW_STATUS" | grep -q "3000.*ALLOW" \
  && success "PASS: port 3000 loopback allow present" \
  || { error "FAIL: port 3000 loopback rule missing"; FIREWALL_FAILED=$((FIREWALL_FAILED + 1)); }

echo "$UFW_STATUS" | grep -q "3001.*DENY" \
  && success "PASS: port 3001 external deny present" \
  || { error "FAIL: port 3001 deny rule missing"; FIREWALL_FAILED=$((FIREWALL_FAILED + 1)); }

echo "$UFW_STATUS" | grep -q "10.0.1.0/24" \
  && success "PASS: monitoring subnet (10.0.1.0/24) rule present" \
  || { error "FAIL: monitoring subnet rule missing"; FIREWALL_FAILED=$((FIREWALL_FAILED + 1)); }

if [[ $FIREWALL_FAILED -gt 0 ]]; then
  error "Phase 5: $FIREWALL_FAILED firewall rule(s) missing — aborting"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
phase 6 "SYSTEMD UNIT FILES (all three inline)"
# ─────────────────────────────────────────────────────────────────────────────

# ─── kk-api.service — target score < 3.5 ─────────────────────────────────────
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
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kk-api

# Hardening (target < 3.5)
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/opt/kijanikiosk/shared/logs /opt/kijanikiosk/health
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
RestrictNamespaces=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
SystemCallArchitectures=native
SystemCallFilter=@system-service
CapabilityBoundingSet=
AmbientCapabilities=
UMask=0027

[Install]
WantedBy=multi-user.target
UNIT
log "Written: /etc/systemd/system/kk-api.service"

# ─── kk-payments.service — target score < 2.5 ────────────────────────────────
# Financial data: strictest hardening
# After/Wants kk-api per requirement
# EnvironmentFile under /opt — unaffected by ProtectSystem=strict (Challenge A)
# IPAddressDeny/Allow used over PrivateNetwork: payments needs controlled egress
cat > /etc/systemd/system/kk-payments.service << 'UNIT'
[Unit]
Description=KijaniKiosk Payments Service
Documentation=https://github.com/GIOVESS/kijanikiosk-devops-foundation
After=network.target kk-api.service
Wants=kk-api.service

[Service]
Type=simple
User=kk-payments
Group=kijanikiosk
EnvironmentFile=/opt/kijanikiosk/config/payments-api.env
ExecStart=/bin/sleep infinity
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kk-payments

# Hardening (target < 2.5)
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
PrivateUsers=yes
ProtectSystem=strict
ProtectHome=yes
ProtectHostname=yes
ProtectClock=yes
ReadWritePaths=/opt/kijanikiosk/shared/logs
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectProc=invisible
ProcSubset=pid
RestrictAddressFamilies=AF_INET AF_UNIX
RestrictNamespaces=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
SystemCallArchitectures=native
SystemCallFilter=@system-service @network-io
SystemCallErrorNumber=EPERM
CapabilityBoundingSet=
AmbientCapabilities=
IPAddressDeny=any
IPAddressAllow=localhost 10.0.1.0/24
UMask=0077

[Install]
WantedBy=multi-user.target
UNIT
log "Written: /etc/systemd/system/kk-payments.service"

# ─── kk-logs.service — target score < 3.5 ────────────────────────────────────
# Integration Challenge C: ExecReload defined so logrotate postrotate can use
# systemctl reload. PrivateTmp does not interfere — SIGHUP is dispatched by
# systemd directly to the main PID, not through the private namespace.
cat > /etc/systemd/system/kk-logs.service << 'UNIT'
[Unit]
Description=KijaniKiosk Log Aggregation Service
Documentation=https://github.com/GIOVESS/kijanikiosk-devops-foundation
After=network.target

[Service]
Type=simple
User=kk-logs
Group=kijanikiosk
EnvironmentFile=/opt/kijanikiosk/config/logs.env
ExecStart=/bin/sleep infinity
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kk-logs

# Hardening (target < 3.5)
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/opt/kijanikiosk/shared/logs /opt/kijanikiosk/health
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_UNIX AF_INET
RestrictNamespaces=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
SystemCallArchitectures=native
SystemCallFilter=@system-service
CapabilityBoundingSet=
AmbientCapabilities=
UMask=0027

[Install]
WantedBy=multi-user.target
UNIT
log "Written: /etc/systemd/system/kk-logs.service"

systemctl daemon-reload

for unit in kk-api kk-payments kk-logs; do
  systemctl enable "${unit}.service"
  log "Enabled: ${unit}.service"
  systemctl restart "${unit}.service" \
    && log "Started: ${unit}.service" \
    || warn "${unit}.service failed to start — inspect: journalctl -u ${unit} -n 30"
done

log "Hardening scores:"
for unit in kk-api kk-logs kk-payments; do
  SCORE=$(systemd-analyze security "${unit}.service" 2>/dev/null \
    | tail -1 | grep -oP '\d+\.\d+' || echo "unknown")
  log "  ${unit}.service: $SCORE"
done

# ─────────────────────────────────────────────────────────────────────────────
phase 7 "JOURNAL PERSISTENCE AND LOG ROTATION"
# ─────────────────────────────────────────────────────────────────────────────

mkdir -p /var/log/journal
mkdir -p /etc/systemd/journald.conf.d

cat > /etc/systemd/journald.conf.d/kijanikiosk.conf << 'CONF'
[Journal]
Storage=persistent
SystemMaxUse=500M
SystemKeepFree=100M
SystemMaxFileSize=50M
MaxRetentionSec=90day
CONF

systemctl restart systemd-journald
log "Journal: persistent storage, 500MB cap, 90-day retention"

# Logrotate config
# su directive: required when target directory is group-writable by non-root
# group. Without it logrotate refuses rotation with "insecure permissions".
# create directive matches directory default ACLs so post-rotation files
# remain writable by kk-api and readable by kk-payments (Challenge C resolved
# via ExecReload in kk-logs.service — systemctl reload signals SIGHUP).
cat > /etc/logrotate.d/kijanikiosk << 'LOGROTATE'
/opt/kijanikiosk/shared/logs/*.log {
    su kk-api kijanikiosk
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 kk-api kijanikiosk
    sharedscripts
    postrotate
        systemctl reload kk-logs.service 2>/dev/null || true
    endscript
}
LOGROTATE
log "Written: /etc/logrotate.d/kijanikiosk (with su directive)"

# Phase 7 inline check (informational)
if logrotate --debug /etc/logrotate.d/kijanikiosk 2>&1 | grep -qi "^error:"; then
  warn "logrotate --debug reported errors — review /etc/logrotate.d/kijanikiosk"
else
  log "logrotate --debug passed cleanly"
fi

# ─────────────────────────────────────────────────────────────────────────────
phase 8 "MONITORING HEALTH CHECKS"
# ─────────────────────────────────────────────────────────────────────────────

mkdir -p /opt/kijanikiosk/health

# Services have no application code — "down" is expected
# A missing file is a script failure; "down" is a valid provisioned state
api_status=$(timeout 2 bash -c "echo >/dev/tcp/localhost/3000" 2>/dev/null \
  && echo '"ok"' || echo '"down"')
payments_status=$(timeout 2 bash -c "echo >/dev/tcp/localhost/3001" 2>/dev/null \
  && echo '"ok"' || echo '"down"')

printf '{"timestamp":"%s","kk-api":%s,"kk-payments":%s}\n' \
  "$(date -Is)" "$api_status" "$payments_status" \
  > /opt/kijanikiosk/health/last-provision.json

# Integration Challenge B: health dir is new — define ownership explicitly
# kk-logs owns runtime health files; kijanikiosk group provides read access
chown kk-logs:kijanikiosk /opt/kijanikiosk/health/last-provision.json
chmod 640 /opt/kijanikiosk/health/last-provision.json

log "Health check JSON written"
log "  kk-api:      $api_status (expected: down — no app code deployed)"
log "  kk-payments: $payments_status (expected: down — no app code deployed)"

# ─────────────────────────────────────────────────────────────────────────────
phase 9 "FINAL VERIFICATION — All Phases"
# ─────────────────────────────────────────────────────────────────────────────

FAILED_CHECKS=()

# Phase 2: accounts
for u in kk-api kk-payments kk-logs; do
  id "$u" &>/dev/null \
    && record_check "$u user exists" pass \
    || record_check "$u user exists" fail
done

getent group kijanikiosk &>/dev/null \
  && record_check "kijanikiosk group exists" pass \
  || record_check "kijanikiosk group exists" fail

for u in kk-api kk-payments kk-logs; do
  id -nG "$u" 2>/dev/null | grep -qw kijanikiosk \
    && record_check "$u in kijanikiosk group" pass \
    || record_check "$u in kijanikiosk group" fail
done

# Phase 3: directories and ACLs
[[ $(stat -c '%a' /opt/kijanikiosk/config) == "750" ]] \
  && record_check "/opt/kijanikiosk/config is 750" pass \
  || record_check "/opt/kijanikiosk/config is 750" fail

getfacl /opt/kijanikiosk/shared/logs 2>/dev/null | grep -q "user:kk-api:rwx" \
  && record_check "shared/logs ACL kk-api:rwx" pass \
  || record_check "shared/logs ACL kk-api:rwx" fail

getfacl /opt/kijanikiosk/shared/logs 2>/dev/null | grep -q "user:kk-payments:r-x" \
  && record_check "shared/logs ACL kk-payments:r-x" pass \
  || record_check "shared/logs ACL kk-payments:r-x" fail

getfacl /opt/kijanikiosk/shared/logs 2>/dev/null | grep -q "default:user:kk-api:rwx" \
  && record_check "shared/logs default ACL kk-api (survives logrotate)" pass \
  || record_check "shared/logs default ACL kk-api (survives logrotate)" fail

for f in api.env payments-api.env logs.env; do
  [[ -f /opt/kijanikiosk/config/$f ]] \
    && record_check "env file exists: $f" pass \
    || record_check "env file exists: $f" fail
done

sudo -u kk-payments test -r /opt/kijanikiosk/config/payments-api.env \
  && record_check "kk-payments can read payments-api.env" pass \
  || record_check "kk-payments can read payments-api.env" fail

# Phase 4: package hold
apt-mark showhold | grep -q nginx \
  && record_check "nginx package held" pass \
  || record_check "nginx package held" fail

# Phase 5: firewall
UFW_OUT=$(ufw status)
echo "$UFW_OUT" | grep -q "22/tcp.*ALLOW" \
  && record_check "ufw: SSH (22) allowed" pass \
  || record_check "ufw: SSH (22) allowed" fail

echo "$UFW_OUT" | grep -q "80/tcp.*ALLOW" \
  && record_check "ufw: HTTP (80) allowed" pass \
  || record_check "ufw: HTTP (80) allowed" fail

echo "$UFW_OUT" | grep -q "3001.*DENY" \
  && record_check "ufw: port 3001 external deny" pass \
  || record_check "ufw: port 3001 external deny" fail

echo "$UFW_OUT" | grep -q "10.0.1.0/24" \
  && record_check "ufw: monitoring subnet 10.0.1.0/24 allow" pass \
  || record_check "ufw: monitoring subnet 10.0.1.0/24 allow" fail

# Phase 6: systemd units
for unit in kk-api kk-payments kk-logs; do
  systemctl is-enabled "${unit}.service" 2>/dev/null | grep -q "enabled" \
    && record_check "${unit}.service enabled" pass \
    || record_check "${unit}.service enabled" fail

  systemctl is-active "${unit}.service" 2>/dev/null | grep -q "active" \
    && record_check "${unit}.service active" pass \
    || record_check "${unit}.service active" fail
done

for unit in kk-api kk-logs; do
  SCORE=$(systemd-analyze security "${unit}.service" 2>/dev/null \
    | tail -1 | grep -oP '\d+\.\d+' || echo "99")
  awk "BEGIN{exit ($SCORE < 3.5) ? 0 : 1}" \
    && record_check "${unit}.service hardening score < 3.5 (${SCORE})" pass \
    || record_check "${unit}.service hardening score < 3.5 (${SCORE})" fail
done

P_SCORE=$(systemd-analyze security kk-payments.service 2>/dev/null \
  | tail -1 | grep -oP '\d+\.\d+' || echo "99")
awk "BEGIN{exit ($P_SCORE < 2.5) ? 0 : 1}" \
  && record_check "kk-payments hardening score < 2.5 (${P_SCORE})" pass \
  || record_check "kk-payments hardening score < 2.5 (${P_SCORE})" fail

# Phase 7: journal + logrotate
[[ -f /etc/systemd/journald.conf.d/kijanikiosk.conf ]] \
  && record_check "journal persistence config exists" pass \
  || record_check "journal persistence config exists" fail

[[ $(journalctl --disk-usage 2>/dev/null) ]] \
  && record_check "journal is active and readable" pass \
  || record_check "journal is active and readable" fail

# Fixed: isolate logrotate exit code from pipefail with || true
LOGROTATE_OUT=$(logrotate --debug /etc/logrotate.d/kijanikiosk 2>&1 || true)
if ! echo "$LOGROTATE_OUT" | grep -qi "error:"; then
  record_check "logrotate config passes --debug" pass
else
  record_check "logrotate config passes --debug" fail
fi

# Phase 8: health check
[[ -f /opt/kijanikiosk/health/last-provision.json ]] \
  && record_check "health check JSON exists" pass \
  || record_check "health check JSON exists" fail

[[ $(stat -c '%a' /opt/kijanikiosk/health/last-provision.json 2>/dev/null) == "640" ]] \
  && record_check "health JSON permissions 640" pass \
  || record_check "health JSON permissions 640" fail

[[ $(stat -c '%U' /opt/kijanikiosk/health/last-provision.json 2>/dev/null) == "kk-logs" ]] \
  && record_check "health JSON owned by kk-logs" pass \
  || record_check "health JSON owned by kk-logs" fail

# ─── Final result ─────────────────────────────────────────────────────────────
echo ""
echo "================================================"
TOTAL_FAILED=${#FAILED_CHECKS[@]}
if [[ $TOTAL_FAILED -eq 0 ]]; then
  success "All checks passed. Server converged to desired state."
  echo "================================================"
  exit 0
else
  error "$TOTAL_FAILED check(s) failed:"
  for check in "${FAILED_CHECKS[@]}"; do
    error "  ✗ $check"
  done
  echo "================================================"
  exit 1
fi
