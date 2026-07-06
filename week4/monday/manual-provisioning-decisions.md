# Manual Provisioning Decisions - KijaniKiosk API Server

| Decision | Value I chose | Reason |
|---|---|---|
| Cloud provider | None — local VirtualBox via Vagrant | No cloud account required; VirtualBox host-only networking reproduces VPC-equivalent isolation locally |
| Region | N/A — local host | Local provisioning has no region concept |
| Operating system | Ubuntu 22.04.5 LTS (jammy) | Matches Week 3 baseline; confirmed via `lsb_release -a` |
| Instance type | 1 vCPU, 1024MB RAM | Smallest size that runs systemd + ufw + nginx without swap pressure |
| VPC | VirtualBox host-only network 192.168.56.0/24 | Local equivalent of a VPC — isolated L2 segment shared by the three KijaniKiosk VMs |
| Subnet | 192.168.56.0/24, static host assignment .11 | Static assignment avoids DHCP-dependent IP discovery |
| Security group | ufw: deny incoming default, allow 22/tcp | Confirmed via provisioner output: "Firewall is active and enabled", "Rule added" |
| SSH key pair | Vagrant-generated per-VM keypair | Vagrant replaces default insecure key on first boot; confirmed in boot log |
| Root volume size | 39G (`/dev/sda1`) | Vagrant box default |
| Public IP? | No — NAT (10.0.2.15) outbound, host-only (192.168.56.11) inter-VM | No externally routable IP needed for staging isolation |
| Tags / labels | None at VM level; deferred to Terraform `tags` block (Wednesday) | Local provisioning has no native tagging system |
