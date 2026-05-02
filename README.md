# LXD Ubuntu VM – Terraform + cloud-init

Deploy an Ubuntu 24.04 virtual machine on LXD via Terraform, with DHCP networking and a pre-configured `ansible` user — all driven by a Gitea CI/CD pipeline.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Ubuntu 24.04 host | With LXD installed via snap |
| MicroK8s + Gitea | With a registered Gitea Actions runner |
| Terraform ≥ 1.5 | Installed on the runner |
| Runner user in `lxd` group | `sudo usermod -aG lxd <runner-user>` |

---

## Repository Secrets & Variables

Configure these in **Gitea → Repository → Settings → Secrets and Variables**:

| Type | Name | Value |
|---|---|---|
| **Secret** | `ANSIBLE_SSH_PUBLIC_KEY` | Contents of your `~/.ssh/id_ed25519.pub` |
| **Variable** | `VM_NAME` | e.g. `ubuntu-vm-01` *(optional, has default)* |

---

## Repository Structure

```
.
├── .gitea/
│   └── workflows/
│       └── terraform.yml        # CI/CD pipeline
├── cloud-init/
│   └── user-data.yaml           # cloud-init template
├── main.tf                      # LXD provider + VM resource
├── variables.tf                 # Input variables
├── outputs.tf                   # VM IP / SSH command
├── terraform.tfvars.example     # Example values (safe to commit)
└── .gitignore
```

---

## Pipeline Behaviour

| Event | Jobs run |
|---|---|
| Push to any branch / PR | `plan` only |
| Push to `main` | `plan` → `apply` |

---

## Local Usage

```bash
# 1. Copy and fill in your values
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and add your ansible_ssh_public_key

# 2. Initialise
terraform init

# 3. Plan
terraform plan

# 4. Apply
terraform apply

# 5. Get SSH command
terraform output ansible_ssh_command
```

---

## cloud-init Details

- **Network:** DHCP on `enp5s0` via netplan
- **Ansible user:** SSH key-only, passwordless sudo, no password set
- **Packages:** curl, wget, git, python3, openssh-server
- **SSH hardening:** password auth disabled, root login disabled

---

## Destroying the VM

```bash
terraform destroy
```
