# KijaniKiosk DevOps Foundation

Production server provisioning foundation for the KijaniKiosk payments platform. This repository contains an idempotent 8-phase bash provisioning script, hardened systemd unit files, an ACL-based access model, and supporting documentation — built to converge a dirty Ubuntu 22.04 server to a defined production state without manual intervention.

---

## Repository Structure

```
kijanikiosk-devops-foundation/
├── Vagrantfile                          # Ubuntu 22.04 VM definition (VirtualBox)
├── kijanikiosk-provision.sh            # 8-phase idempotent provisioning script
├── pre-provisioning-audit.txt          # Dirty state captured before first run
├── provision-run-dirty.log             # First run output (dirty VM)
├── provision-run-clean.log             # Second run output (idempotency proof)
├── post-remediation-verification.txt   # logrotate access model test results
├── post-remediation-verification-commands.sh
├── access-model-final.md               # Full ACL and ownership model
├── kk-payments-hardening.md            # Hardening score progression log
├── hardening-decisions.md              # Security decisions in plain language (for Nia)
├── integration-notes.md                # Four integration conflict resolutions
└── reflection.md                       # Engineering retrospective
```

---

## The 8 Phases

| Phase | Name | Key Actions |
|---|---|---|
| 1 | Pre-flight | Detect dirty state, log each condition found |
| 2 | Service Accounts | Create `kk-api`, `kk-payments`, `kk-logs`, `kijanikiosk` group |
| 3 | Directories + ACLs | `/opt/kijanikiosk/` tree with extended and default ACLs |
| 4 | Package Pinning | Unhold → install nginx → re-hold at current repo version |
| 5 | Firewall | Full ufw reset, intent-based rules with comments, programmatic verification |
| 6 | systemd Units | All three unit files written inline, hardened, enabled, started |
| 7 | Journal + Logrotate | Persistent journal capped at 500MB, logrotate with `su` directive |
| 8 | Health Checks | Port probes → `/opt/kijanikiosk/health/last-provision.json` |

---

## Services

| Service | Port | Hardening Score | Target |
|---|---|---|---|
| `kk-api` | 3000 | 1.8 | < 3.5 |
| `kk-payments` | 3001 | 1.2 | < 2.5 |
| `kk-logs` | internal | 1.8 | < 3.5 |

---

## Running the Script

```bash
# Start the VM
vagrant up
vagrant ssh

# First run (dirty state convergence)
sudo bash /vagrant/kijanikiosk-provision.sh 2>&1 | tee /vagrant/provision-run-dirty.log

# Second run (idempotency proof — must also exit 0)
sudo bash /vagrant/kijanikiosk-provision.sh 2>&1 | tee /vagrant/provision-run-clean.log
```

Expected: all Phase 9 checks pass, `exit 0` on both runs.

---

## Dirty State Handled

The script explicitly detects and converges each of the following conditions found on the pre-provisioned VM:

- `kk-api` absent due to UID 998 conflict — created without forced UID
- `kk-payments` and `kk-logs` existing but not in `kijanikiosk` group — memberships corrected
- `/opt/kijanikiosk/config` permissions at 777 — corrected to 750
- No extended ACLs on `shared/logs/` — applied with default ACLs for logrotate survival
- Spurious `ufw deny 3001` rule from prior manual edit — full ruleset reset
- `nginx` package on manual hold — unhold → version check → re-hold
- `kk-api.service` existing without hardening (score 9.6) — overwritten with hardened unit

---

## Integration Challenges Resolved

See `integration-notes.md` for full decision rationale on:

- **A** — `ProtectSystem=strict` vs `EnvironmentFile` path
- **B** — Health directory ownership in the ACL model
- **C** — logrotate `postrotate` signal under `PrivateTmp=yes`
- **D** — Package hold lifecycle on dirty VM

---

## Branch Strategy

```
main
└── develop
    └── feature/week3-production-foundation  ← this PR
```
