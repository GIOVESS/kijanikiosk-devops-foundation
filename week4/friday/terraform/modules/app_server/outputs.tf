output "public_ip" { value = var.vm_ip }
output "ssh_command" { value = "ssh -i ${var.ssh_key_path} vagrant@${var.vm_ip}" }
