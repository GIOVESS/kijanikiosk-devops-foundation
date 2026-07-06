variable "name" {
  description = "Short server key (api, payments, logs)"
  type        = string
}
variable "vm_ip" {
  description = "Static private-network IP of this server's Vagrant VM"
  type        = string
}
variable "ssh_key_path" {
  description = "Path to this VM's Vagrant-generated private key"
  type        = string
}
variable "environment" {
  description = "Deployment environment tag"
  type        = string
  default     = "staging"
}
