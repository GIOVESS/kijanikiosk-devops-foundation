# nologin vs false vs locked — Decision Document

**Reviewer:** Tendo  
**Decision:** `/usr/sbin/nologin` for all three service accounts

---

## The Three Options

### /usr/sbin/nologin
When set as a user's shell, `nologin` executes if someone attempts an interactive
login as that user. It prints a configurable message ("This account is currently
not available") and exits with a non-zero code, refusing the session. Critically,
it does this at the shell level — after PAM authentication has already completed.

**Mechanism:** The login process (sshd, su, login) checks whether the shell is
a valid login shell by consulting `/etc/shells`. `nologin` is not listed there.
When the shell is not in `/etc/shells`, login daemons that respect this list
refuse interactive sessions. Additionally, `nologin` itself refuses to provide
a shell even if invoked directly.

### /bin/false
Immediately exits with status code 1. No message, no shell, no interaction.
Functionally prevents login but provides no feedback to the person attempting
access. Does not print an explanation — the connection simply closes.

**Mechanism:** The shell field in `/etc/passwd` is set to `/bin/false`. Any
process that attempts to exec this shell gets an immediate non-zero exit. There
is no distinction between "account disabled" and "something went wrong."

### Locked account (passwd -l / usermod -L)
Places a `!` prefix on the password hash in `/etc/shadow`, preventing password
authentication. Does not affect SSH key authentication — a locked account with
an authorized SSH key can still log in via key. Does not prevent `su` by root.

**Mechanism:** PAM's `pam_unix` module checks for the `!` prefix during
password verification and rejects it. Key-based auth bypasses this entirely.

---

## Decision: /usr/sbin/nologin

**Chosen for all three service accounts (kk-api, kk-payments, kk-logs).**

### Why not /bin/false
`/bin/false` works but provides zero operational visibility. When a junior
engineer or automated tool attempts to `su` to a service account for debugging
and gets a silent failure, the next 20 minutes are spent wondering whether the
account exists, whether su is broken, or whether the shell path is wrong.
`nologin` makes the intent explicit: "this account exists and is intentionally
non-interactive."

### Why not locked account
Locking the password hash does not prevent key-based SSH login. For a production
server where service accounts should never have interactive sessions under any
circumstances, relying on a lock that SSH key auth bypasses is insufficient.
`nologin` as the shell prevents interactive sessions regardless of authentication
method.

### Why /usr/sbin/nologin
It communicates intent at the system level. Any tool that reads `/etc/passwd`
(monitoring agents, audit scripts, security scanners) immediately sees that these
accounts are service identities, not human accounts. The message it prints is
configurable via `/etc/nologin.txt` if a custom explanation is needed. It is the
standard convention for service accounts on Linux systems and is what tools like
`useradd --system` implicitly expect.

### Service-account-specific note
All three accounts were created with `--no-create-home` in addition to
`--shell /usr/sbin/nologin`. The combination means: no home directory to
SSH into, no shell to execute, no password hash to crack. The account exists
solely as a kernel-level identity for process ownership and file permissions.
