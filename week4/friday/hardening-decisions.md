# KijaniKiosk Staging Environment — Hardening Decisions

## For Nia

This document explains, in plain terms, how we protect the three services that make up KijaniKiosk's staging environment — the API, the payments processor, and the log aggregator — and what risks each protection addresses. It also describes what we can honestly claim about repeatability, and what our current setup does not yet cover.

### How the environment is built

Each of the three servers is created the same way, from the same template, using an automated tool rather than a person clicking through setup screens. This matters because a person configuring three servers by hand will inevitably do something slightly differently each time — forget a setting, mistype a value, or apply a fix to one server and forget the other two. Automating the build removes that inconsistency entirely. The same template that creates the API server creates the payments server and the log server, with only the specific details (name, network address) changed.

### How the environment is configured

Once a server exists, a second automated tool configures it: creating the accounts each service runs under, setting up file permissions, installing the software each service needs, and applying firewall rules. This tool is designed so that running it a second time on an already-configured server changes nothing — it simply confirms everything is still correct. We proved this by running it twice in sequence and confirming the second run reported zero changes on all three servers.

### Control summary

| Control | What it does | Risk mitigated |
|---|---|---|
| Dedicated service accounts per function | Each service (API, payments, logs) runs under its own restricted account that cannot log in interactively | If one service is compromised, the attacker cannot use that access to log in as a person or pivot to other services |
| Firewall default-deny | All network traffic is blocked unless explicitly allowed | Prevents any unexpected or forgotten network exposure — only the ports we deliberately open are reachable |
| Payments service network allowlist | The payments service can only be reached from the internal monitoring network, never from the open internet | Limits the payments service's attack surface to trusted internal systems only, since it handles financial data |
| Filesystem write restriction | Each service can only write to its own designated log folder; the rest of the system is locked read-only from the service's perspective | If a service is compromised, the attacker cannot modify system files, install persistent malware, or tamper with other services' data |
| No privilege escalation | Services are blocked from gaining higher permissions than they start with, even if a bug in the service code tries to request them | Closes a common technique attackers use to go from limited access to full control of a server |
| Isolated temporary storage | Each service gets its own private temporary file space, invisible to other services | Prevents one service from reading or interfering with another service's temporary data |
| Restricted system call access | Each service is only allowed to perform the specific low-level operations a normal network service needs; everything else is blocked | Even if an attacker finds a bug in the service code, most attack techniques rely on system operations that are simply not available to try |
| Payments service network egress allowlist | The payments service can only initiate outbound connections to the internal monitoring network; all other outbound network access is blocked | Prevents a compromised payments service from being used to exfiltrate data to an external destination |
| Configuration file permissions | Each service's settings file (which may contain sensitive values) is only readable by that service's own account | Prevents one service, or an unrelated user account, from reading another service's configuration secrets |
| Automated log rotation | Log files are automatically compressed and cycled on a schedule, with old logs eventually deleted | Prevents disk space exhaustion, which could otherwise cause services to fail |

### What proves this is repeatable

Nia, when you ask what evidence we have that this environment is genuinely reproducible and not a one-time manual setup: we ran the entire build-and-configure process twice, back to back. The first run creates everything from nothing. The second run, against the exact same starting point, reported zero infrastructure changes and zero configuration changes across all three servers. That combination — nothing to build, nothing to fix — is the proof. If we deleted this entire environment today and ran the same two steps again, we would get an identical result, because the process is written down as a specification and executed by machine, not carried in anyone's memory or judgment calls made on the day.

### What this does not protect against

This hardening addresses the servers themselves — their accounts, their files, their network exposure, and their configuration integrity. It does not address the application code that will eventually run inside these services; that code has not been written yet, so we cannot yet evaluate its security. It does not include intrusion detection or alerting — if a firewall rule blocks an attack attempt, nothing currently notifies a person that it happened. It does not cover encryption of data at rest on these servers. Finally, our environment currently uses a local storage system without the safety mechanism that prevents two people from making conflicting changes to the same infrastructure at the same time; on a team larger than one engineer, this would need to be addressed before this pattern is used for a shared, actively-developed environment.
