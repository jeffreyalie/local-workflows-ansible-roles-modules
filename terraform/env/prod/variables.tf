# ---------------------------------------------------------------------------
# LXD Provider Configuration
# ---------------------------------------------------------------------------

variable "lxd_address" {
  type = string
}

# variable "lxd_trust_password" {
#   type        = string
#   description = "The trust password for the LXD host"
#   sensitive   = true
# }

# ---------------------------------------------------------------------------
# VM Configuration (defined in tfvars)
# ---------------------------------------------------------------------------

variable "vm_name" {
  type = string
}

variable "os_type" {
  type    = string
  description = "Combined in locals to form vm name"
}

variable "environment" {
  type        = string
  description = "Passed from GHA input TFVAR_environment (e.g. dev, staging, prod) amd Combined in locals to form vm name"
}

variable "image" {
  type    = string
  default = "ubuntu-24-04-vm"
}

variable "network" {
  type    = string
  default = "lxdbr0"
}

variable "storage_pool" {
  type = string
}

variable "disk_size" {
  type = string
}

variable "cpu_count" {
  type = number
}

variable "memory_size" {
  type = string
}

# ---------------------------------------------------------------------------
# SSH Configuration (Ansible) - cloud init will use this to setup the VM for Ansible access
# ---------------------------------------------------------------------------

variable "ansible_ssh_public_key" {
  type = string
}
