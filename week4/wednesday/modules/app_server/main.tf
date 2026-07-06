resource "null_resource" "this" {
  triggers = { ip = var.vm_ip }
  connection {
    type        = "ssh"
    host        = var.vm_ip
    user        = "vagrant"
    private_key = file(var.ssh_key_path)
  }
  provisioner "remote-exec" {
    inline = ["echo 'Connected to kijanikiosk-${var.name} (${var.environment})'", "uname -a"]
  }
}
