# KijaniKiosk Access Model — Final

**Last updated:** 2026-06-22  
**Maintainer:** Provisioning script (kijanikiosk-provision.sh)  
**Baseline:** Tuesday lab + Wednesday additions + Friday health dir + logrotate interaction

---

## Service Accounts

| Account | UID | Shell | Purpose |
|---|---|---|---|
| `kk-api` | 995 (assigned — 998 conflict) | `/usr/sbin/nologin` | API service process |
| `kk-payments` | 997 | `/usr/sbin/nologin` | Payments service process |
| `kk-logs` | 996 | `/usr/sbin/nologin` | Log aggregation, health file ownership |

**Shared group:** `kijanikiosk` (GID 1002) — all three service accounts are members. Used for group-level read grants across the directory tree.

---

## Directory Tree

```
/opt/kijanikiosk/              root:kijanikiosk  750
├── config/                    root:kijanikiosk  750
│   ├── api.env                kk-api:kijanikiosk    640
│   ├── payments-api.env       kk-payments:kijanikiosk 640
│   └── logs.env               kk-logs:kijanikiosk   640
├── shared/
│   └── logs/                  kk-api:kijanikiosk  2750 + ACLs
└── health/                    root:kijanikiosk  750
    └── last-provision.json    kk-logs:kijanikiosk 640
```

---

## ACL Detail: `/opt/kijanikiosk/shared/logs/`

```
# Standard permissions
owner: kk-api
group: kijanikiosk
mode:  2750 (setgid — new files inherit kijanikiosk group)

# Extended ACLs (current entries)
user:kk-api:rwx      — writes log entries
user:kk-payments:r-x — reads for audit correlation
user:kk-logs:rwx     — aggregates and manages log files

# Default ACLs (propagate to new files on creation)
default:user:kk-api:rwx
default:user:kk-payments:r-x
default:user:kk-logs:rwx
```

**Verification:**
```bash
getfacl /opt/kijanikiosk/shared/logs/
```

---

## Health Directory: `/opt/kijanikiosk/health/` (added Friday)

**Access decision:** Health directory is new — not in Tuesday's original model.

- Root writes the directory itself (provisioning runs as root)
- `kk-logs` owns runtime files (natural owner of monitoring artifacts, consistent with its role)
- `kijanikiosk` group provides read access to all service accounts and any future monitoring user
- No extended ACLs required: `750` on directory + `640` on files + group membership is sufficient
- If a dedicated monitoring account is introduced later, adding it to `kijanikiosk` is the correct extension path — no ACL changes needed

**Ownership:**
```
/opt/kijanikiosk/health/          root:kijanikiosk  750
/opt/kijanikiosk/health/*.json    kk-logs:kijanikiosk 640
```

---

## Logrotate Interaction Notes

**Challenge:** `logrotate`'s `create` directive sets standard ownership and mode on the new file after rotation. It does **not** re-apply extended ACLs. If the directory's default ACLs are missing, rotated log files will be inaccessible to `kk-payments` and `kk-logs`.

**Resolution:**

1. `create 0640 kk-api kijanikiosk` in `/etc/logrotate.d/kijanikiosk` sets base ownership
2. Default ACLs on `shared/logs/` (set with `setfacl -d`) propagate automatically to any new file created inside the directory — including the replacement file logrotate creates
3. The setgid bit (`2750`) ensures group inheritance even for files created by tools that don't explicitly set group

**Definitive test (run after forced logrotate):**
```bash
sudo logrotate --force /etc/logrotate.d/kijanikiosk
sudo -u kk-api touch /opt/kijanikiosk/shared/logs/test-write.tmp \
  && echo "PASS: kk-api can write after logrotate" \
  || echo "FAIL: kk-api write failed post-rotation"
getfacl /opt/kijanikiosk/shared/logs/
```

Expected: `PASS` + default ACLs visible on new files.

---

## Config Directory Access

`/opt/kijanikiosk/config/` is `750` (root:kijanikiosk). Each env file is `640` owned by its service account.

**Read path:** service → EnvironmentFile → `chown kk-payments:kijanikiosk payments-api.env 640`  
→ owner read (kk-payments), group read (kijanikiosk members), no other access.

`ProtectSystem=strict` in systemd units makes `/etc` read-only for service processes. Config under `/opt` is unaffected — this is why all env files are under `/opt/kijanikiosk/config/` and not `/etc/`.

---

## Who Can Read What (summary matrix)

| Path | kk-api | kk-payments | kk-logs | root | kijanikiosk group |
|---|---|---|---|---|---|
| `config/api.env` | ✓ (owner) | ✗ | ✗ | ✓ | r (group) |
| `config/payments-api.env` | ✗ | ✓ (owner) | ✗ | ✓ | r (group) |
| `config/logs.env` | ✗ | ✗ | ✓ (owner) | ✓ | r (group) |
| `shared/logs/` | rwx (ACL) | r-x (ACL) | rwx (ACL) | ✓ | r-x (group) |
| `health/last-provision.json` | r (group) | r (group) | ✓ (owner) | ✓ | r (group) |
