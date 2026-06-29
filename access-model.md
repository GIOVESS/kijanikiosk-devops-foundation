# KijaniKiosk Access Model — Tuesday Lab

**Date:** 2026-06-24  
**Author:** Giovess  
**Status:** Verified — all isolation tests passed

---

## Design Table

| Path | Owner | Group | Mode | ACLs | Reasoning |
|---|---|---|---|---|---|
| `/opt/kijanikiosk/` | root | kijanikiosk | 755 | none | Top-level owned by root — no service writes here directly |
| `/opt/kijanikiosk/api/` | kk-api | kk-api | 750 | none | Only the API service needs access — no cross-service reads |
| `/opt/kijanikiosk/payments/` | kk-payments | kk-payments | 750 | none | Financial code isolated — no other service should traverse this path |
| `/opt/kijanikiosk/logs/` | kk-logs | kk-logs | 750 | none | Log aggregator owns its working directory exclusively |
| `/opt/kijanikiosk/config/` | root | kijanikiosk | 750 | vagrant:r-x | Root owns secrets; group read allows all service accounts to access their own env files |
| `/opt/kijanikiosk/config/db.env` | root | kijanikiosk | 640 | vagrant:r-- | Database credentials — group read only, no execute |
| `/opt/kijanikiosk/config/payments-api.env` | root | kijanikiosk | 640 | vagrant:r-- | Payment API keys — same model as db.env |
| `/opt/kijanikiosk/shared/logs/` | kk-logs | kijanikiosk | 2770 | kk-api:rwx, kk-payments:r-x, vagrant:r-x | Cross-service log sharing requires ACLs; basic mode alone cannot express three different permission levels |
| `/opt/kijanikiosk/scripts/deploy.sh` | root | root | 750 | none | Deployment script — root owns, group execute removed, SUID cleared |

---

## Decision Reasoning

### Why 750 on service directories (not 700)
Mode 700 would prevent the owning group from traversing the directory. Using 750
with the service account's primary group keeps the door open for future tooling
(monitoring agents, deployment scripts) to be added to that group without
changing the mode. The risk is minimal because no other user is currently in
`kk-api`'s primary group.

### Why root owns config (not the service accounts)
If `kk-api` owned `config/`, a compromised `kk-api` process could modify its own
environment file — changing `DB_HOST` to redirect database connections, or
injecting environment variables that alter application behaviour on restart.
Root ownership prevents this. Service accounts can read (via group membership)
but cannot write.

### Why ACLs on shared/logs instead of basic permissions
Basic Unix permissions express exactly three permission sets: owner, group, other.
`shared/logs/` needs four different levels: `kk-logs` (rwx), `kk-api` (rwx),
`kk-payments` (r-x), and `vagrant` (r-x). The group bit can only satisfy one of
these. ACLs are the correct tool when more than two non-root principals need
different permissions on the same resource.

### Why setgid (2770) on shared/logs
Without the setgid bit, files created inside `shared/logs/` by `kk-api` would
inherit `kk-api`'s primary group (`kk-api`), not `kijanikiosk`. The ACL grants
would still apply to the directory itself but new files would be inaccessible to
`kk-payments` via group read. The setgid bit forces all new files to inherit the
`kijanikiosk` group, making default ACLs effective on every file created.

### Why vagrant is in the kijanikiosk group
The `vagrant` user represents the operations engineer (Amina's role in this lab).
Adding them to `kijanikiosk` provides read access to shared/logs and config
through group membership — the minimum needed to inspect the running system
without requiring sudo for routine log reads.

---

## Verified Isolation

```
PASS: kk-api cannot access /opt/kijanikiosk/payments/
PASS: kk-payments cannot access /opt/kijanikiosk/api/
PASS: kk-api can read /opt/kijanikiosk/config/db.env (via kijanikiosk group)
PASS: SUID scan of /opt/kijanikiosk returned empty
```
