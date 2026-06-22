# Integration Notes — Four Challenge Resolutions

---

## Challenge A: ProtectSystem=strict and EnvironmentFile

**Conflict:**  
`ProtectSystem=strict` mounts `/usr`, `/boot`, and `/etc` read-only for the service process. If `EnvironmentFile` pointed to `/etc/kijanikiosk/payments-api.env`, the service would silently fail to load its configuration — systemd would not report a clear error, it would just start the process without the environment variables set.

**Options considered:**

1. Keep env files under `/etc/kijanikiosk/` and add `ReadWritePaths=/etc/kijanikiosk` to the unit — this would work but defeats the purpose of `ProtectSystem=strict` for the most sensitive path on the filesystem
2. Keep env files under `/opt/kijanikiosk/config/` — outside `ProtectSystem` scope, no exception needed
3. Use `ProtectSystem=full` instead (less restrictive, allows `/etc` reads) — reduces hardening score and is harder to justify to auditors

**Decision:** Option 2. All env files live under `/opt/kijanikiosk/config/`, which is unaffected by `ProtectSystem=strict`. `ReadWritePaths` grants write access only to the log directory. No carve-outs required in `/etc`.

**Why:** The env file path is a deployment decision, not a system requirement. Choosing `/opt` costs nothing and avoids punching a hole in the filesystem hardening. This is also consistent with the principle that `/etc` should hold system-managed configuration, not runtime secrets for individual services.

**Verification:** `sudo -u kk-payments cat /opt/kijanikiosk/config/payments-api.env` must return the file contents (or empty file), not `Permission denied`.

---

## Challenge B: Monitoring User and ACL Defaults for Health Directory

**Conflict:**  
Phase 8 runs as root. Left unchecked, `last-provision.json` would be owned `root:root` with default permissions. The `kijanikiosk` group (which all service accounts and any future monitoring account belong to) would have no read access without `sudo`.

**Options considered:**

1. `chown root:kijanikiosk` on the file + `chmod 640` — group read, no other access
2. Extended ACL on `/opt/kijanikiosk/health/` with `setfacl` for each reader — more granular but unnecessary complexity for a single file
3. Create a dedicated `kk-monitor` account — premature; the monitoring stack isn't defined yet

**Decision:** `kk-logs:kijanikiosk 640` on the file, `root:kijanikiosk 750` on the directory.

**Why:** `kk-logs` is the natural owner of monitoring artifacts — its role is log aggregation and health reporting. The `kijanikiosk` group membership already covers all service accounts that need read access. Any future dedicated monitoring account simply needs to be added to `kijanikiosk` — no ACL changes required. No extended ACLs needed; mode + group ownership is sufficient for this use case.

**Access model addition:** `/opt/kijanikiosk/health/` is now formally part of the access model with its own ownership row (see `access-model-final.md`).

---

## Challenge C: logrotate postrotate and PrivateTmp

**Conflict:**  
`kk-logs.service` has `PrivateTmp=yes`. After logrotate rotates a log file, `kk-logs` must re-open its file handles to write to the new file — otherwise it continues writing to the now-rotated (and compressed) old file. The standard mechanism is a `postrotate` signal.

The risk: `systemctl reload kk-logs.service` only works if the unit defines `ExecReload=`. Without it, systemd treats `reload` as `restart`, which is disruptive and drops buffered log data. Additionally, `PrivateTmp=yes` creates a private `/tmp` namespace — if logrotate tried to use a temp file intermediary, it would fail.

**Options considered:**

1. `systemctl restart kk-logs.service` in postrotate — works but restarts the process, dropping in-flight log data
2. `systemctl kill -s HUP kk-logs.service` — sends SIGHUP directly to the main PID via systemd. Works regardless of `ExecReload=`. More explicit.
3. Define `ExecReload=/bin/kill -HUP $MAINPID` in the unit + use `systemctl reload` in postrotate — clean separation: the unit advertises how to reload; logrotate uses the standard interface

**Decision:** Option 3. `ExecReload=/bin/kill -HUP $MAINPID` is defined in `kk-logs.service`. Postrotate script uses `systemctl reload kk-logs.service`.

**Why:** `systemctl reload` is the correct abstraction — it signals "re-read config / re-open files" without restarting the process. `PrivateTmp` is irrelevant here because the SIGHUP is dispatched by systemd to the main PID directly — it does not pass through the private namespace. Defining `ExecReload=` also makes the unit self-documenting: anyone inspecting the service knows exactly how it handles log rotation signals.

---

## Challenge D: Dirty VM and Package Holds

**Conflict:**  
The dirty VM had `nginx` on hold from a manual `apt-mark hold` earlier in the week. A naive `apt-get install nginx` would fail silently (hold prevents installation). A naive `apt-mark hold nginx` at the end of the script would succeed even if the installed version was wrong.

**Options considered:**

1. Detect hold, fail loudly, require manual intervention — safe but breaks the idempotency requirement
2. Unhold → check installed version against repo candidate → install only if they differ → re-hold — fully automated, deterministic

**Decision:** Option 2.

**Implementation:**
```bash
apt-mark unhold nginx                                          # clear existing hold
INSTALLED=$(dpkg-query -W -f='${Version}' nginx || echo none)
CANDIDATE=$(apt-cache policy nginx | grep Candidate | awk '{print $2}')
# install only if mismatch or not present
apt-mark hold nginx                                            # re-pin current version
```

**Why:** The hold lifecycle is a script concern, not an operator concern. Failing loudly for a recoverable state (wrong hold) is appropriate for infrastructure that has human operators available — but the project spec requires convergence on dirty state without manual steps. The version check prevents silent downgrades: if someone had upgraded nginx intentionally, the script detects the mismatch and installs the candidate (repo version), then logs it. This is auditable.

**What we chose not to do:** Pin to a hardcoded version string (e.g., `1.18.0-6ubuntu14.15`). On a different VM or after an OS security patch, that string may not exist in the repo, causing the script to fail. Pinning to "whatever the repo's current candidate is and then holding" is more portable.
