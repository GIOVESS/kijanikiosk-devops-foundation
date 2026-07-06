#!/usr/bin/env bash
set -uo pipefail

REPO_ROOT="/home/giovess/kijanikiosk-devops-foundation"
TF_DIR="$HOME/kijanikiosk-infra"
ANSIBLE_DIR="$HOME/kijanikiosk-ansible"

log() { echo "[$(date -Is)] $*"; }

log "Ensuring Vagrant VMs are up..."
cd "$REPO_ROOT" || exit 1
vagrant up || { echo "FAIL: vagrant up"; exit 1; }

log "Running Terraform apply..."
cd "$TF_DIR" || exit 1
terraform init -input=false >/dev/null 2>&1
terraform apply -auto-approve -input=false || { echo "FAIL: terraform apply"; exit 1; }

log "Extracting server IPs from Terraform output..."
IPS_JSON=$(terraform output -json server_ips) || { echo "FAIL: terraform output"; exit 1; }
API_IP=$(echo "$IPS_JSON" | jq -r '.api')
PAYMENTS_IP=$(echo "$IPS_JSON" | jq -r '.payments')
LOGS_IP=$(echo "$IPS_JSON" | jq -r '.logs')

log "Writing inventory.ini..."
cat > "$ANSIBLE_DIR/inventory.ini" << INV
[kijanikiosk]
api-staging      ansible_host=${API_IP}
payments-staging ansible_host=${PAYMENTS_IP}
logs-staging     ansible_host=${LOGS_IP}

[kijanikiosk:vars]
ansible_user=vagrant
ansible_python_interpreter=/usr/bin/python3
INV

log "Running Ansible playbook..."
cd "$ANSIBLE_DIR" || exit 1
ansible-playbook -i inventory.ini kijanikiosk.yml || { echo "FAIL: ansible-playbook"; exit 1; }

log "Pipeline completed successfully."
exit 0
