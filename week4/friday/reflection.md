# Week 4 Friday — Reflection

## 1. Where two requirements conflicted

The provisioning script's ACL model (kk-api rwx, kk-payments r-x, kk-logs rwx on the shared log directory) assumed all three services co-located on one server — true for the Week 3 single-VM target, false once the Friday brief split them across three VMs. Each host now only has one of the three service accounts, so `setfacl` failed trying to resolve UIDs that don't exist on that host (`kk-payments` doesn't exist on `api-staging`). Fix: per-host single-owner directories (`log_dir` owned by whichever `service_name` runs on that host) replace the cross-service ACL grants. This is the direct equivalent of the brief's Challenge D — a directive that worked under one topology assumption broke under another, and the fix required understanding *why* the original model existed (shared filesystem, multiple readers) before removing what no longer applied.

## 2. Rewriting one sentence for Tendo

Nia version: "Each service can only write to its own designated log folder; the rest of the system is locked read-only from the service's perspective."

Tendo version: "ProtectSystem=strict mounts /usr, /boot, and /etc read-only in the unit's private mount namespace; ReadWritePaths grants the sole writable exception to /opt/kijanikiosk/shared/logs."

Lost: the plain-language framing that lets a non-technical stakeholder reason about blast radius without knowing what a mount namespace is. Gained: the exact mechanism and directive name, which is what's needed to reproduce, audit, or debug the control — Tendo needs to know it's `ProtectSystem=strict` specifically, not a firewall rule or a permissions chmod, because that's what he'd grep for in the unit file.

## 3. Most fragile handoff

The Terraform-to-Ansible IP handoff via `terraform output -json` piped through `jq`, written into `inventory.ini` by `pipeline.sh`. It works here because the topology is fixed and known (three static IPs, one Vagrantfile). In a real environment, this breaks the moment server count changes dynamically (autoscaling, spot replacement) or the output schema changes shape without the script being updated in lockstep — `jq -r '.api'` has no error handling if `.api` doesn't exist, it just silently emits `null` into the inventory and Ansible fails opaquely against a host with hostname "null". To make this robust in a real target environment I'd need: schema validation on the Terraform output before writing inventory, a fallback/abort path if any IP resolves empty, and ideally a dynamic inventory plugin (Terraform's own or a custom one) instead of a bash string-templated file, so the two tools' data models don't drift out of sync silently.
