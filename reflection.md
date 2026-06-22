# Reflection

## 1. When did two requirements conflict, and what did you learn from resolving it?

The conflict surfaced during Phase 3 and Phase 7 simultaneously. Setting `ProtectSystem=strict` on `kk-payments` was necessary to hit the 2.5 hardening target. But the EnvironmentFile had initially been considered at `/etc/kijanikiosk/payments-api.env` — a path that `ProtectSystem=strict` makes read-only for the service process. The service would start and appear healthy while silently running without any environment variables loaded.

The resolution was architectural, not a directive tweak: move all env files to `/opt/kijanikiosk/config/`, which `ProtectSystem=strict` does not restrict. The lesson was that hardening directives interact with deployment decisions, not just with each other. A score that looks correct on paper can mask a service that is misconfigured at runtime. The pre-start readability check (`sudo -u kk-payments test -r ...`) was added specifically because of this — it forces the conflict to surface during provisioning rather than during an incident.

---

## 2. Rewrite one sentence from the Nia document in technical language. What is lost and what is gained?

**Original (for Nia):**
> "All elevated operating system privileges are stripped from the service at startup."

**Rewritten (for Tendo):**
> "`CapabilityBoundingSet=` is set to empty, removing all POSIX capabilities from the service process at exec time, which prevents privilege escalation via `setuid` binaries, raw socket creation, and kernel operations regardless of file capability bits."

**What is lost:** Nia can act on the original sentence — she understands the business implication (reduced blast radius if the service is compromised) without needing to know what a capability is. The technical version requires her to context-switch into implementation detail before she can evaluate risk.

**What is gained:** Tendo can verify it. The technical version is falsifiable — `systemd-analyze security` will confirm or contradict the claim. It also communicates scope precisely: "all elevated privileges" is vague enough to be disputed; "empty `CapabilityBoundingSet`" is not. The translation loss is that Nia's document becomes a reference artifact rather than a communication tool.

---

## 3. What is the most fragile part of the provisioning script in a real production environment?

The firewall phase. Specifically, the `ufw --force reset` at the start of Phase 5.

On this VM, ufw is the only firewall layer. In a real production environment, the server likely sits behind a cloud security group or a hardware firewall, and there may be additional ufw rules managed by other tooling — monitoring agents, VPN clients, intrusion detection systems. A full reset followed by re-application of only the rules this script knows about would silently drop those rules, potentially cutting off the server from its management plane in the window between reset and re-enable.

To make it robust, the script would need to: (1) query the target environment's firewall management ownership before resetting, (2) export and diff existing rules against intended rules rather than replacing wholesale, or (3) switch from `ufw reset` to a declarative tool like `nftables` with atomic rule replacement. What we would need to know about the target environment: whether ufw is the sole firewall layer, whether any rules are injected by agents outside our control, and whether there is a console or out-of-band access path that survives a firewall misconfiguration.
