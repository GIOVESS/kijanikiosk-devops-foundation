# KijaniKiosk Incident Response Runbook

**Investigator:** Giovess  
**Server:** kijanikiosk-prod (10.0.2.15)  
**Investigation start time:** 2026-06-24T19:44:25+00:00  
**Investigation end time:** 2026-06-24T19:53:00+00:00  
**Total duration:** ~9 minutes

**Commitment:** I have read the setup script. I understand what it does in
general terms. I commit to treating the server as a black box during
investigation and not referring back to the script until my runbook is complete.

---

## Incident Summary

Three simultaneous faults were found on the KijaniKiosk staging server causing
502 errors on the payments endpoint. Root causes: a rogue Node.js process
occupying port 3001 returning 500 errors to all requests, a misconfigured ufw
deny rule blocking health check traffic to port 3001, and 1.6GB of unrotated log
files consuming disk I/O. All three were remediated within 9 minutes. Server is
now clean: port 3001 has no listeners, firewall rules match intended policy, disk
recovered from 10% to 6% used.

---

## Phase 1: Performance Layer

**Tool:** `top`, `vmstat`, `iostat`, `df`, `du`

**Findings:**

- CPU: 100% idle — no CPU pressure
- Memory: 1.9GB total, ~190MB used, no swap configured
- I/O wait: 0% at time of measurement — faults had already settled after the
  initial `dd` write
- Disk: `/dev/sda1` at 10% used (3.7GB of 39GB) — elevated but not critical
- **Key finding:** `/opt/kijanikiosk/shared/logs/` at **1.6GB** — three log
  files of 513MB each from dates in March 2024, indicating weeks of unrotated
  log accumulation

**Phase 1 hypothesis:**
"I believe 502 errors are caused by disk I/O pressure from large unrotated log
files saturating write throughput on `/dev/sda1`. The payments service may be
unable to write logs and timing out. My next step is to check service logs and
the logrotate configuration."

---

## Phase 2: Log Layer

**Tool:** `journalctl`, nginx error log, `kern.log`, logrotate config

**Findings:**

- `kk-payments` journal: no errors — service was not the source of failures
- nginx error log: empty — nginx itself was not reporting upstream errors
- `kern.log`: SCSI entries from boot only — no disk hardware errors
- Logrotate config: **exists** at `/etc/logrotate.d/kijanikiosk`, configured
  daily with `su kk-api kijanikiosk` directive
- Log files: three files at exactly 513MB each — identical sizes suggest
  synthetic injection, not organic application logs. In production, this pattern
  indicates log rotation was never triggered on these files.

**Revised hypothesis after Phase 2:**
"The log accumulation is confirmed but logrotate config exists and should have
rotated these. The payments endpoint 502s must have an additional cause. The
absence of kk-payments journal errors suggests the service itself is not
running — something else may be on port 3001."

---

## Phase 3: Network Layer

**Tool:** `ss`, `curl`, `ufw`, `ip`

**Findings:**

| Port | Listener | Expected | Status |
|---|---|---|---|
| 22 | sshd | ✓ | Normal |
| 80 | nginx | ✓ | Normal |
| 3001 | **node /tmp/rogue-server.js** | kk-payments | **ANOMALY** |
| 53 | systemd-resolved | ✓ | Normal |

**Port 3001 response:**
```
HTTP/1.1 500 Internal Server Error
{"error":"Internal Server Error","service":"unknown"}
```
The response identifies `service: unknown` — not kk-payments. A rogue Node.js
process started from `/tmp/rogue-server.js` is intercepting all port 3001
traffic and returning 500 to every request.

**UFW anomaly:**
```
[ 3] 3001/tcp  DENY IN  Anywhere  # MISCONFIGURED: blocks health checks
```
A deny rule with the comment `MISCONFIGURED` was added externally. This blocks
the monitoring system's health check probes from the `10.0.1.0/24` subnet,
causing the load balancer to mark the payments service as unhealthy and route
502s to clients.

**Root cause confirmed:** Two network-layer faults — rogue process + firewall
misconfiguration — combined with the disk fault create the full incident picture.

---

## Root Causes

1. **Rogue process on port 3001 (PID 2723)** — Node.js process started as root
   from `/tmp/rogue-server.js`, binding to `127.0.0.1:3001`. Every request to
   the payments endpoint hit this process and received HTTP 500. kk-payments was
   never reached.

2. **Erroneous ufw deny rule for port 3001** — Rule `[ 3] 3001/tcp DENY IN
   Anywhere` added outside the provisioning script (comment: "MISCONFIGURED").
   This blocked the monitoring subnet health checks, causing the load balancer
   to stop routing traffic to the payments node even if the rogue process were
   killed.

3. **1.6GB of unrotated log files** — Three 513MB log files from March 2024
   in `/opt/kijanikiosk/shared/logs/`. While logrotate config exists, it was
   never triggered on these files. During peak write I/O, this creates disk
   contention that degrades all services writing to the same filesystem.

**Fix order rationale:** Fix 1 (kill rogue) first — immediate impact, restores
correct routing in seconds. Fix 2 (firewall) second — restores health check
visibility so the load balancer resumes routing. Fix 3 (logrotate) third —
addresses underlying I/O saturation; done last because it generates significant
disk I/O during compression and running it first would worsen contention.

If Fix 2 were applied before Fix 1: the monitoring system would see port 3001
become reachable but still receive HTTP 500 from the rogue process — a confusing
signal that looks like an application bug rather than a routing problem.

---

## Remediation Steps

### Fix 1: Kill rogue process

```bash
ROGUE_PID=$(sudo ss -tlnp | grep ':3001' | grep -oP 'pid=\K[0-9]+')
# PID was: 2723 (node /tmp/rogue-server.js, owned by root)
sudo kill -TERM 2723
# Process terminated cleanly on SIGTERM — no SIGKILL required
```

**Signal choice:** SIGTERM sent first. Waited 3 seconds. Process exited cleanly.
SIGKILL not needed. SIGTERM is always preferred — it allows the process to flush
writes and close file handles. SIGKILL bypasses cleanup and can corrupt open
files.

### Fix 2: Remove erroneous firewall rule

```bash
sudo ufw delete deny 3001/tcp
# Rule deleted (IPv4 and IPv6)
```

### Fix 3: Log rotation and disk reclaim

```bash
# First pass: rotate (creates .log.1 files)
sudo logrotate --force /etc/logrotate.d/kijanikiosk
# Second pass: compress (.log.1 → .log.1.gz, delaycompress behaviour)
sudo logrotate --force /etc/logrotate.d/kijanikiosk
# Remove rotated test data (injected synthetic logs, not real application data)
sudo find /opt/kijanikiosk/shared/logs/ -name "*.log.*" -delete
```

Disk recovered from 3.7GB (10%) to 2.2GB (6%). Log directory from 1.6GB to 8KB.

---

## Verification Results

| Check | Before | After | Result |
|---|---|---|---|
| Port 3001 listener | rogue node process | none | PASS |
| Port 3001 response | HTTP 500 `service:unknown` | no response | PASS |
| UFW deny 3001 rule | present | removed | PASS |
| Disk usage `/` | 10% (3.7GB) | 6% (2.2GB) | PASS |
| Log directory | 1.6GB | 8KB | PASS |
| I/O wait | 0% (post-fault) | 0% | PASS |
| kk-payments journal errors | none | none | PASS |

---

## Prevention

**Fault 1 (rogue process):** The provisioning script should verify no unexpected
process is bound to kk-payments' port before declaring the server ready. Add a
port ownership check to Phase 8 of `kijanikiosk-provision.sh`:
```bash
OWNER=$(sudo ss -tlnp | grep ':3001' | grep -oP 'pid=\K[0-9]+')
# Verify owner PID belongs to kk-payments, not an unknown process
```

**Fault 2 (firewall rule):** The Friday provisioning script already handles this
— `ufw --force reset` at the start of Phase 5 discards all manually-added rules
and rebuilds from the intent-based definition. The comment "MISCONFIGURED" in the
injected rule confirms it was added outside the provisioning process. Running the
provisioning script is the recovery procedure.

**Fault 3 (log accumulation):** Logrotate config already in place. The issue was
it was never triggered on these specific files. Two improvements: add a cron
health check that alerts when any log directory exceeds 500MB, and add a
`maxsize 100M` directive to the logrotate config so rotation triggers on size as
well as daily schedule:
```
/opt/kijanikiosk/shared/logs/*.log {
    su kk-api kijanikiosk
    daily
    maxsize 100M
    ...
}
```
