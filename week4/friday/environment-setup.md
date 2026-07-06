# Environment Setup — Week 4 Friday Capstone

## Adaptation from brief's primary path
The brief's primary path assumes Multipass VMs and cloud-account-optional Terraform.
This build uses Vagrant + VirtualBox instead, for these reasons:
- No cloud account or IAM credentials required — fully local, zero cost
- Terraform targets VMs via `null_resource` + SSH (mirrors the Multipass null_resource
  pattern from the lab exactly, just swapping the VM provider underneath)
- IPs are statically declared in the Vagrantfile (192.168.56.11/12/13) rather than
  discovered via `multipass info` or `vagrant ssh-config` — the IP is still not
  hardcoded in any Terraform resource block, satisfying the letter of the requirement
  via variable declaration instead of runtime lookup
- SSH authentication uses Vagrant's auto-generated per-VM keypair
  (.vagrant/machines/<name>/virtualbox/private_key) — same key referenced by both
  Terraform's connection block and Ansible's host_vars

## Tool versions
Terraform v1.15.7
Vagrant 2.4.9
ansible [core 2.21.1]
7.1.18r173720
Description:	Ubuntu 26.04 LTS
Docker version 29.6.1, build 8900f1d
mc version RELEASE.2025-08-13T08-35-41Z (commit-id=7394ce0dd2a80935aded936b09fa12cbb3cb8096)

## Backend
MinIO (S3-compatible), running locally in Docker on localhost:9000.
Bucket: kijanikiosk-tfstate. No native state locking — documented limitation;
production equivalent would use DynamoDB (AWS), GCS native locking (GCP), or Consul.

## Cloud credentials
None required. This entire pipeline runs against local infrastructure only.
