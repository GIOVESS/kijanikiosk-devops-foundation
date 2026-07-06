# KijaniKiosk API Server - Desired State Specification

## Identity
- Name: kijanikiosk-api-staging
- Environment tag: staging
- Owner tag: amina

## Compute
- Provider: VirtualBox (via Vagrant)
- Region: local (no cloud region)
- Instance type: 1 vCPU / 1024MB RAM
- Operating system: ubuntu/jammy64 (Ubuntu 22.04.5 LTS)
  # Note: becomes a Terraform variable, not a data source lookup — no image
  # registry to query locally; explicit adaptation for the non-cloud path.

## Networking
- VPC: VirtualBox host-only network, CIDR 192.168.56.0/24
- Subnet: 192.168.56.0/24
- Assign public IP: no

## Access Control
- SSH access: port 22, source — host machine only (host-only adapter, not internet-reachable)
- HTTP access: port 80, source 0.0.0.0/0 (kk-api reverse proxy target, per Week 3 ufw rules)
- All other inbound: deny
- All outbound: allow

## Storage
- Root volume: 39GB (Vagrant box default)

## Authentication
- SSH key pair name: Vagrant per-VM auto-generated key at `.vagrant/machines/kijanikiosk-api/virtualbox/private_key`

## What must NOT exist on this server after provisioning
- No default password authentication (key-only, enforced by Vagrant's insecure-key replacement)
- No services listening other than sshd until Ansible configures kk-api
- No world-writable directories outside /tmp

## Open questions
- Whether MinIO's lack of native state locking is acceptable for a single-operator lab environment (resolved: documented as a known limitation, not blocking)
- Whether the NAT adapter (10.0.2.15) needs firewall consideration alongside the host-only adapter (resolved: NAT is Vagrant-internal only)

## Hardest Decision and Why
Static IP assignment vs. dynamic discovery. The brief's primary path assumes Multipass with `multipass info` for IP lookup; Vagrant with VirtualBox host-only networking makes static declaration in the Vagrantfile more idiomatic, but shifts "dynamic IP capture" from a runtime lookup to a variable declaration. Defensible — no resource block hardcodes the IP — but it's a deviation from the letter of the requirement worth flagging explicitly.
