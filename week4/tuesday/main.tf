terraform {
  required_providers {
    null = { source = "hashicorp/null", version = "~> 3.2" }
  }
}

variable "vm_ip" {
  type        = string
  description = "Static private-network IP of the kijanikiosk-api Vagrant VM"
}
variable "environment" {
  type        = string
  description = "Deployment environment tag"
  default     = "staging"
}
variable "ssh_key_path" {
  type        = string
  description = "Path to the Vagrant-generated private key for kijanikiosk-api"
}

resource "null_resource" "kijanikiosk_api" {
  triggers = { ip = var.vm_ip }
  connection {
    type        = "ssh"
    host        = var.vm_ip
    user        = "vagrant"
    private_key = file(var.ssh_key_path)
  }
  provisioner "remote-exec" {
    inline = ["echo 'Connected to kijanikiosk-api (${var.environment})'", "uname -a"]
  }
}
