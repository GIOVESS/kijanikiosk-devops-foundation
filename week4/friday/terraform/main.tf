terraform {
  required_providers {
    null = { source = "hashicorp/null", version = "~> 3.2" }
  }
}

variable "vagrant_repo_path" {
  description = "Absolute path to the kijanikiosk-devops-foundation repo checkout"
  type        = string
}
variable "environment" {
  description = "Deployment environment tag"
  type        = string
  default     = "staging"
}

locals {
  servers = {
    api      = { ip = "192.168.56.11" }
    payments = { ip = "192.168.56.12" }
    logs     = { ip = "192.168.56.13" }
  }
}

module "app_servers" {
  source       = "./modules/app_server"
  for_each     = local.servers
  name         = each.key
  vm_ip        = each.value.ip
  environment  = var.environment
  ssh_key_path = "${var.vagrant_repo_path}/.vagrant/machines/kijanikiosk-${each.key}/virtualbox/private_key"
}
