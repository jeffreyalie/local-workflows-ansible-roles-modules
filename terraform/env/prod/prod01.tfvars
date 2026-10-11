# ---------------------------------------------------------------
# Rename this file to terraform.tfvars and fill in your values.
# DO NOT commit terraform.tfvars with real keys to the repository.
# Use Gitea Secrets (TF_VAR_ansible_ssh_public_key) instead.
# ---------------------------------------------------------------

# vm_name = Combination of input from GHA and os_type

# Paste your ansible user's SSH public key here
# ansible_ssh_public_key = "ssh-ed25519 AAAA... user@host"

storage_pool = "default"
os_type      = "ubuntu-vm"
image        = "ubuntu-24-04-vm"
network      = "lxdbr0"
disk_size    = "10GiB"
cpu_count    = 2
memory_size  = "2GiB"
