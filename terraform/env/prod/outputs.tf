# Outputs for the prod environment

output "vm_name" {
  value = module.vm.vm_name
}

output "vm_ip" {
  value = module.vm.vm_ip
}

output "vm_mac_address" {
  value = module.vm.vm_mac_address
}

output "ansible_ssh_command" {
  value = module.vm.ansible_ssh_command
}
