module "vm" {
  source = "../../modules/lxd-vm"

  vm_name                = var.vm_name
  os_type                = var.os_type
  environment            = var.environment
  ansible_ssh_public_key = var.ansible_ssh_public_key
  lxd_address            = var.lxd_address
  # lxd_trust_password     = var.lxd_trust_password --- IGNORE if using client certificates ---
  image                  = var.image
  network                = var.network
  storage_pool           = var.storage_pool
  disk_size              = var.disk_size
  cpu_count              = var.cpu_count
  memory_size            = var.memory_size
}
