# KijaniKiosk API Server — Triage Report

**Date:** 2026-06-24  
**Investigated by:** Giovess  
**Server:** kijanikiosk-prod (10.0.2.15)  
**Incident start (approximate):** 2024-01-15 04:07:55 UTC (from log evidence)

---

## Summary

A Python3 process consuming 522MB (~26% of total RAM) is running unchecked with
no swap configured, creating memory pressure that will trigger the OOM killer if
left running. A 283MB orphaned log file exists at
`/var/log/kijanikiosk/access.log.1` indicating log rotation failure. Log evidence
shows the likely root cause of the reported latency degradation: database
connection pool exhaustion beginning at 04:07:55, escalating to full connection
failure by 06:22:28. No application service is currently bound to ports 3000 or
3001 — only nginx (80) and SSH (22) are listening.

---

## Process and Resource State

**Top process by memory:** `python3` PID 14306 — 25.9% MEM, 522MB RSS, 7.2% CPU.
Running as root. Command: allocating 500 x 1MB blocks in a loop then sleeping.
This is an abnormal process with no legitimate application function — it exists
solely to consume memory.

**Memory totals:**
- Total: 1.9GB
- Used: 684MB
- Available: 1.1GB
- Swap: **0B** — no swap configured

With 522MB held by the rogue python3 process and no swap, the system has limited
headroom. A second similar process or an application memory spike would push usage
above the OOM threshold.

**No zombie processes** detected. No processes in D (uninterruptible sleep) state.

**Other notable processes:** `multipathd`, `snapd`, `packagekitd` — all system
daemons within normal memory ranges (20–38MB). nginx master at 12MB — normal.

---

## Filesystem and Disk

**Disk usage:** `/dev/sda1` at 6% (2.1GB of 39GB) — not a current crisis but the
log directory is growing.

**`/var/log/kijanikiosk/`:** 271MB total. The dominant file:

```
283MB   /var/log/kijanikiosk/access.log.1
```

This is a single orphaned rotated log file that was never compressed or deleted.
The `.1` suffix indicates logrotate attempted rotation but the `compress` step
did not complete or the rotation config is absent. At the current write rate, this
directory will continue growing.

`/var/log/journal/` at 17MB — normal.

No partition is above 80% used. Disk is not the immediate cause of latency but
the 283MB file is evidence of a broken logrotate configuration that will become
a disk issue over time.

---

## Log Analysis

**Error frequency from `/var/log/kijanikiosk/app.log`:**

| Count | Error type |
|---|---|
| 2 | Query timeout (30000ms) |
| 2 | ECONNREFUSED database:5432 |
| 1 | Connection pool exhausted |
| 1 | Memory usage at 87% |
| 1 | Retry limit reached |

**Timeline — how the failure escalated:**

```
03:12  Worker started normally
03:14  First request processed successfully (112ms — baseline healthy)
03:45  DB connection pool at 85% — first warning
04:01  DB connection pool at 94% — approaching limit
04:07  Pool exhausted — requests begin queuing       ← LATENCY SPIKE STARTS HERE
04:08  Query timeouts (2x, 30s each) — p95 latency degrading
04:09  Memory at 87% — likely from queued requests accumulating in memory
06:22  ECONNREFUSED database:5432 — database unreachable, retrying
06:22  Retry limit reached — application can no longer process any requests
```

**Root cause of latency increase:** The p95 degradation from 120ms to 480ms
correlates directly with the 04:07 pool exhaustion event. When the pool is
exhausted, incoming requests queue in memory waiting for a connection. Queue
wait time is added to every request's response time — a request that normally
takes 120ms now waits 300ms+ for a connection before processing begins.

No OOM or disk I/O errors in syslog — the kernel has not yet intervened.

---

## Network and Service State

**Listening ports:**

| Port | Process | Expected |
|---|---|---|
| 22 | sshd | ✓ |
| 80 | nginx | ✓ |
| 53 | systemd-resolved | ✓ (DNS) |
| 3000 | — | ✗ MISSING — kk-api not running |
| 3001 | — | ✗ MISSING — kk-payments not running |
| 5432 | — | ✗ MISSING — database not running locally |

**HTTP response:** `HTTP 200 — 0.000751s` — nginx responds correctly on port 80
but is serving the default page. No application behind it.

**TCP connection distribution:**
- LISTEN: 5 (normal)
- TIME-WAIT: 3 (normal — recent connections closed cleanly)
- ESTAB: 1 (the current SSH session)

No connection accumulation, no SYN flood indicators.

---

## Assessment

**Likely root cause of the reported latency increase:**

The database connection pool was undersized relative to request volume. As traffic
grew, the pool filled (03:45–04:01), then exhausted (04:07). From that point every
request queued for a connection slot, adding variable wait time to p95 latency.
The pool exhaustion then contributed to memory pressure (queued requests held in
memory), which the log recorded at 04:09. By 06:22 the database itself became
unreachable — either it crashed under connection pressure or was restarted without
the application being notified.

The current rogue python3 process (PID 14306) is a separate compounding issue —
it is consuming 522MB of a 1.9GB system with no swap, which will accelerate any
future OOM event.

---

## Recommended Next Steps

**1. Terminate the rogue python3 process immediately**
```bash
kill -TERM 14306
# Verify:
ps -p 14306
```
This recovers 522MB and removes the OOM risk. Do this before any other action.

**2. Fix the database connection pool configuration**
The pool must be sized above peak concurrent request volume. Increase
`DB_POOL_MAX` in the application environment config and restart the API service.
Add pool utilisation to the monitoring dashboard so the 85% threshold triggers
an alert before exhaustion occurs.

**3. Fix log rotation and clean up the orphaned file**
```bash
sudo logrotate --force /etc/logrotate.d/kijanikiosk
# If no config exists:
sudo truncate -s 0 /var/log/kijanikiosk/access.log.1
```
Ensure a working logrotate config is in place before the next deployment.
The 283MB file is not causing current issues but will cause a disk-full incident
within weeks at current growth rates.
