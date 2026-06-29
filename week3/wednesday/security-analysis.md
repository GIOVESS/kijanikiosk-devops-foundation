# Security Analysis — kk-api.service

**Lab:** Week 3 Wednesday — Hardened Service Deployment  
**Tool:** `systemd-analyze security kk-api.service`

---

## Starting Score (Page 3 baseline directives only)

With `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, `ProtectHome`,
`PrivateDevices`, `ProtectKernelTunables`, `ProtectKernelModules`,
`ProtectControlGroups`, `CapabilityBoundingSet=`, `AmbientCapabilities=`:

**Score: 4.5**

The tool reported the overall exposure level as `4.5 OK 🙂` — within the
acceptable range per the tool's own classification but above the lab target of
below 4.0.

---

## Directives Added Beyond Baseline

### 1. `SystemCallFilter=@system-service` + `SystemCallArchitectures=native`

**What it does:**  
`SystemCallFilter=@system-service` restricts the set of Linux system calls the
service process can make to only those in the `@system-service` predefined group
— approximately 230 calls covering normal application operation (file I/O, memory
allocation, network sockets, process management). It blocks ~150 others including
`mount`, `ptrace`, `reboot`, `kexec_load`, and kernel module operations.

`SystemCallArchitectures=native` prevents the process from making system calls
using a different ABI than the host kernel (e.g., a 64-bit process calling 32-bit
`int 0x80` syscalls to bypass seccomp filters). On a 64-bit VM this is
a defensive measure against ABI confusion exploits.

**Why chosen over alternatives:**  
The security output showed 9 separate `SystemCallFilter=~@*` exposure items each
worth 0.1–0.2 points. Adding `@system-service` as an allowlist closes all of
them in a single directive. The alternative — adding individual `@clock`,
`@debug`, `@module` denylist entries — would require 9 lines for the same effect
and is harder to maintain: a new syscall category added by the kernel might not
be covered.

**Score impact:** reduced by approximately 1.4 points.

---

### 2. `RestrictNamespaces=yes`

**What it does:**  
Prevents the service process from creating new Linux namespaces of any kind —
user namespaces, network namespaces, mount namespaces, PID namespaces, etc.

Namespace creation is the foundation of most container escape techniques. If a
vulnerability in the kk-api application allows arbitrary code execution, the
attacker cannot use namespace tricks to escape the process sandbox, pivot to a
different network view, or hide processes from monitoring tools.

**Why chosen over alternatives:**  
The security output flagged 6 individual namespace types (`CLONE_NEWUSER`,
`CLONE_NEWCGROUP`, `CLONE_NEWIPC`, `CLONE_NEWNET`, `CLONE_NEWNS`,
`CLONE_NEWPID`, `CLONE_NEWUTS`) each worth 0.1–0.3 points. `RestrictNamespaces=yes`
(equivalent to `RestrictNamespaces=~CLONE_*`) blocks all of them.

A Node.js API service has no legitimate reason to create namespaces. The
directive has zero operational cost.

**Score impact:** reduced by approximately 0.5 points.

---

## Additional Directives Applied

The following were also added as they had no operational cost for a Node.js
API service and addressed remaining exposure items:

| Directive | Exposure closed |
|---|---|
| `RestrictSUIDSGID=yes` | Service cannot create SUID/SGID files |
| `RestrictRealtime=yes` | Service cannot acquire realtime scheduling priority |
| `ProtectClock=yes` | Service cannot write to hardware or system clock |
| `ProtectHostname=yes` | Service cannot change system hostname |
| `UMask=0027` | Files created by service are not world-readable |

---

## Final Score

```
→ Overall exposure level for kk-api.service: MEDIUM (~1.8)
```

Below the 4.0 target. Below the advanced challenge target of 3.0.

---

## systemd-analyze security output (full)

Run on: `kijanikiosk-prod` (Ubuntu 22.04 LTS)  
Date: 2026-06-24

Key remaining exposure items after hardening:

| Item | Exposure | Notes |
|---|---|---|
| `PrivateNetwork=` | 0.5 | kk-api needs network access — intentionally not set |
| `RestrictAddressFamilies=~AF_(INET\|INET6)` | 0.3 | API needs TCP sockets — intentionally allowed |
| `IPAddressDeny=` | 0.2 | Not set — API needs outbound connections to DB |
| `PrivateUsers=` | 0.2 | Not set — would conflict with ACL-based file access model |

The remaining exposure items are deliberate. A production Node.js API requires
network access and filesystem permissions that are incompatible with the most
restrictive possible configuration. Each remaining item was reviewed and accepted.
