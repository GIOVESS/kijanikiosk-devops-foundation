output "server_ips" {
  value = { for k, v in module.app_servers : k => v.public_ip }
}
output "ssh_commands" {
  value = { for k, v in module.app_servers : k => v.ssh_command }
}
