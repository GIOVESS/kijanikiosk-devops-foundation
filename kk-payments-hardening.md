# kk-payments.service — Hardening Log

**Target:** score < 2.5  
**Final score:** 1.2  
**Service status:** active (running) at all score checkpoints

---

## Starting Point

Stub unit from Wednesday lab (no hardening beyond `User=`):

```ini
[Unit]
Description=KijaniKiosk API stub

[Service]
ExecStart=/bin/sleep infinity
User=kk-api
```

```
systemd-analyze security kk-api.service | tail -1
→ Overall exposure level: UNSAFE (9.6)
```

Score: **9.6**

---

## Iteration Log

### Round 1 — Basic isolation

Added:
```ini
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
```

- `NoNewPrivileges`: prevents service from gaining elevated privileges via setuid binaries
- `PrivateTmp`: private `/tmp` and `/var/tmp` — prevents tmp-based privilege escalation between services
- `PrivateDevices`: removes access to physical devices (`/dev/*`)

Score after: **~5.5**  
Service start: ✓

---

### Round 2 — Filesystem hardening

Added:
```ini
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/opt/kijanikiosk/shared/logs
```

- `ProtectSystem=strict`: mounts `/usr`, `/boot`, `/etc` read-only for the service process
- `ProtectHome=yes`: makes home directories inaccessible
- `ReadWritePaths`: explicitly grants write access only to the log directory

**Integration Challenge A:** `ProtectSystem=strict` makes `/etc` read-only. EnvironmentFile originally considered at `/etc/kijanikiosk/payments-api.env` would fail silently. Moved to `/opt/kijanikiosk/config/payments-api.env` — outside ProtectSystem scope.

Score after: **~3.8**  
Service start: ✓ (after env file path corrected)

---

### Round 3 — Kernel + namespace hardening

Added:
```ini
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
RestrictNamespaces=yes
LockPersonality=yes
```

Score after: **~2.9**  
Service start: ✓

---

### Round 4 — Syscall + memory hardening

Added:
```ini
MemoryDenyWriteExecute=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
SystemCallArchitectures=native
SystemCallFilter=@system-service @network-io
SystemCallErrorNumber=EPERM
CapabilityBoundingSet=
AmbientCapabilities=
```

- `CapabilityBoundingSet=` (empty): drops all Linux capabilities — service cannot escalate to any privileged operation
- `SystemCallFilter=@system-service @network-io`: allows only syscalls needed for a network service. Blocks `ptrace`, `mount`, `reboot`, and ~200 others.
- `SystemCallErrorNumber=EPERM`: blocked syscalls return permission denied rather than killing the process — avoids crashes on unexpected calls

Score after: **~2.3**  
Service start: ✓

---

### Round 5 — Identity + network isolation (final)

Added:
```ini
PrivateUsers=yes
ProtectHostname=yes
ProtectClock=yes
ProtectProc=invisible
ProcSubset=pid
RestrictAddressFamilies=AF_INET AF_UNIX
IPAddressDeny=any
IPAddressAllow=localhost 10.0.1.0/24
UMask=0077
```

- `PrivateUsers=yes`: service sees a private user namespace — its UID appears as a different (unprivileged) UID to the host kernel
- `IPAddressDeny=any` + `IPAddressAllow`: network-layer allowlist. Service can only reach localhost and the monitoring subnet. External payment processor egress would require adding their CIDR here.
- `ProtectProc=invisible`: service cannot see other processes in `/proc`
- `UMask=0077`: all files created by the service default to `600` — no group or other read

Score after: **1.2**  
Service start: ✓

---

## Directives Investigated and Rejected

### `PrivateNetwork=yes`

**What it does:** Gives the service a private, isolated network namespace with only a loopback interface. No external network access whatsoever.

**Score impact:** Would reduce score by ~0.3 further.

**Why rejected:** A payments service must connect to external payment processors (Stripe, M-Pesa API, etc.). `PrivateNetwork=yes` would silently prevent all outbound payment calls — the service would appear to run but every transaction would fail at the network layer. `IPAddressDeny`/`IPAddressAllow` achieves network restriction with surgical precision while preserving the ability to add payment gateway CIDRs.

---

### `DynamicUser=yes`

**What it does:** Creates an ephemeral, randomised UID for each service invocation. No static user account required.

**Score impact:** Would improve score by ~0.2.

**Why rejected:** Incompatible with the static ACL model on `/opt/kijanikiosk/shared/logs/`. The directory's extended ACLs grant access by static UID (`user:kk-payments:r-x`). A dynamic user gets a different UID per invocation — the ACL grant would never match. The service would lose read access to audit logs on every restart, breaking correlation between payment events and log records.

---

## Final Unit File

```ini
[Unit]
Description=KijaniKiosk Payments Service
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
```

**Final score: 1.2** — well below the 2.5 target. Service starts and runs correctly at this score.
