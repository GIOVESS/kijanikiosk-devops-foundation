# KijaniKiosk Payments Server — Security Foundation

**Prepared for:** Nia Osei, Chief Product Officer  
**Date:** 22 June 2026  
**Subject:** Security decisions made in preparing the production payments server

---

## What This Document Covers

This document explains the security choices made in building the dedicated server that will host KijaniKiosk's payments service. Each decision is explained in plain terms — what risk it addresses and what it does not. The final section is honest about what this foundation does not yet protect against, because overstating security posture is itself a risk.

---

## Why a Dedicated Server

Running the payments service on a shared application server means that a problem in one service — a bug, a compromised dependency, a misconfigured permission — can affect the others. Separating the payments service onto its own server creates a hard boundary. If something goes wrong with the general API, the payments service is unaffected. Regulators and auditors recognise this separation as a meaningful control.

---

## Security Decisions

| Control | What it does | Risk mitigated |
|---|---|---|
| Dedicated service accounts | Each service runs as its own identity with no login access to the server | Prevents one compromised service from reading another service's files or configuration |
| Read-only system files | The payments process cannot modify core system configuration, even if it is taken over | Limits the damage an attacker can cause if they gain control of the service process |
| Capability removal | All elevated operating system privileges are stripped from the service at startup | Prevents the service from performing administrative actions it has no business need for |
| Firewall intent rules | Network access is defined by purpose, not history; rules are commented and reviewed | Closes ports left open from manual changes; ensures only intended traffic reaches the server |
| Internal-only service port | The payments API port is blocked from all external traffic; only the internal load balancer can reach it | Prevents direct external access to the financial service, forcing all traffic through the controlled ingress point |
| Monitoring subnet restriction | The health check endpoint is accessible only from the designated monitoring network | Prevents external parties from probing service availability or inferring transaction load from health data |
| Process identity isolation | The payments process operates in a private identity space, invisible to other processes on the server | Reduces the ability of a compromised process to observe or interfere with other running services |
| Package version locking | Software versions are fixed and cannot be automatically updated | Prevents an unplanned update from introducing a breaking change or vulnerability into a production environment without review |
| Audit log persistence | System logs are written to permanent storage with a defined 90-day retention | Provides an evidence trail for incident investigation and satisfies basic audit requirements |
| Log access controls | Each service can only read the logs it is permitted to see | Prevents the payments service from accessing application logs it has no need to read |

---

## How These Controls Work Together

The controls above are not independent. Each layer assumes the previous one has failed. If a software vulnerability allows an attacker to control the payments process, the capability removal means they cannot become an administrator. If they work around that, the read-only filesystem means they cannot alter system configuration. If they attempt to reach external infrastructure they should not contact, the network allowlist blocks them. This is defence in depth — no single control is relied upon alone.

---

## What This Foundation Does Not Protect Against

This document would be misleading without acknowledging the gaps.

The server is hardened, but the application itself is not yet deployed. The security of the actual payments software — how it validates inputs, how it handles authentication tokens, whether it is vulnerable to injection attacks — is entirely separate from the server foundation and is not addressed here. A hardened server running vulnerable application code is still vulnerable. Application-level security review should be scheduled before the payments service accepts live transactions.

This foundation also does not include intrusion detection, file integrity monitoring, or automated alerting on anomalous behaviour. Logs are persisted and accessible, but nobody is watching them in real time. Defining who reviews these logs, how often, and what constitutes an alert is the next step after deployment.

Finally, secrets management — the credentials and keys the payments service uses to connect to payment processors — is currently handled through configuration files on the server. This is an acceptable starting point but not a long-term posture. A dedicated secrets management system should be evaluated before transaction volumes become significant.

The access model defined here governs which service can read which files. It does not govern what happens to data after it leaves this server — data in transit between the server and payment processors, or between the server and the database, requires separate controls such as encrypted connections and certificate validation.
