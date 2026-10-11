# LXD Ubuntu VM — Terraform + Ansible + Gitea Actions

Deploy Ubuntu 24.04 virtual machines on LXD via Terraform (module-based), configure them with Ansible roles, all driven by local Gitea CI/CD workflows.

---

## Table of Contents

- [Summary](#summary)
- [Prerequisites](#prerequisites)
- [Quick Steps to Deploy a VM](#quick-steps-to-deploy-a-vm)
- [Architecture Overview](#architecture-overview---infrastrucutre---gha-workflow---secrets-workflow)
- [Repository Structure](#repository-structure)
- [Secrets & Variables](#secrets--variables)
- [Workflows](#workflows)
- [Terraform: Resource Model](#terraform-resource-model)
- [Ansible: Playbook & Roles](#ansible-playbook--roles)
- [End-to-End Deployment Flow](#end-to-end-deployment-flow)
- [Local Usage](#local-usage)
- [Destroying a VM](#destroying-a-vm)
- [Design Notes](#design-notes)
- [Created and Maintained By](#infrastructure-created-and-maintained-by)

---

## Summary

This repository implements a complete infrastructure-as-code solution that:

- Provisions Ubuntu 24.04 VMs on LXD using Terraform with a reusable `lxd-vm` module
- Configures VMs with cloud-init for automated setup
- Deploys applications via Ansible playbooks and local roles
- Manages environments (dev/prod) with separate state management per VM in MinIO
- Provides CI/CD automation through local Gitea Actions workflows

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Ubuntu 24.04 host | LXD installed via snap, API at `https://localhost:8443` |
| Gitea | Running at `http://gitea.local`, `Infra` org |
| Gitea Act Runner | Docker-based runner registered to the `Infra` org |
| MinIO | S3-compatible state backend at `http://10.248.42.22:9000` |
| Terraform ≥ 1.5 | Installed on the runner |
| LXD TLS certificates | Client cert/key for runner-to-LXD authentication |

---

## Quick Steps to Deploy a VM

1. **Clone the repo and create a feature branch**
   ```bash
   git clone http://gitea.local/infra/local-workflows-ansible-roles-modules.git
   cd local-workflows-ansible-roles-modules
   git checkout -b <env><vm_name>   # e.g. dev dev02
   ```

2. **Create a new `.tfvars` file** under `terraform/env/<env>/` — copy an existing one and adjust resources as needed (image, cpu, memory, disk)

3. **Run Terraform Check and Plan** via Gitea Actions — go to Actions → `Terraform Check` / `Terraform Plan`, select your feature branch, enter environment and VM name

4. **Run Ansible Check** via Gitea Actions — go to Actions → `Ansible Check`, select your feature branch to lint and syntax-check the playbook

5. **Open a PR and merge** to `main` — the Check workflows run automatically on the PR; merge once green

6. **Run Terraform Apply** via Gitea Actions — go to Actions → `Terraform Apply`, select `main` branch, enter environment and VM name; the VM is created on LXD

7. **Run Ansible Deploy** via Gitea Actions — go to Actions → `Ansible Deploy`, select `main` branch, enter environment and VM name; Ansible roles are applied to the live VM

8. **Run Terraform Destroy** (when done) via Gitea Actions — go to Actions → `Terraform Destroy`, select `main` branch, enter environment, VM name, and type `yes` to confirm

---

## Architecture Overview - (Infrastrucutre - GHA workflow - Secrets workflow)

```
                ┌─────────────────────────────────────────┐
                │           Gitea (gitea.local)           │   (Org level secrets)
                │   local-workflows-ansible-roles-modules │
                └─────────────────┬───────────────────────┘
                                  │ Gitea Actions triggers
                                  ▼
              ┌───────────────────────────────────────────┐
              │     Gitea Act Runner                      │  (Docker-based, inside LXD VM) --- (Picks secrets from Org)
              └───────┬───────────────────────────┬───────┘
                      │                           │
             Terraform│                           │Ansible
                      ▼                           ▼
              ┌─────────────────┐           ┌─────────────────┐
              │      MinIO      │           │   Target VM     │
              │    backend s3   │           │  (Ubuntu 24.04) │
              │    (TF state)   │           │  ansible user   │
              └─────────────────┘           └─────────────────┘
                      │                    
                      │ Creates VM
                      │ 
              ┌─────────────────┐ 
              │   LXD / KVM     │ 
              │  (localhost:    │ 
              │    8443)        │ 
              └─────────────────┘  
      
```

**This repo uses a module-based Terraform layout:**
- Each environment (`dev`, `prod`) has its own root module under `terraform/env/<env>/` that calls the shared `lxd-vm` module
- The `lxd-vm` module encapsulates all LXD resource definitions and cloud-init rendering
- Gitea Actions workflows are defined locally in `.gitea/workflows/` — not shared/reusable
- Ansible uses local roles — no Ansible Galaxy or centralised role server

---

## Repository Structure

```
.
├── .gitea/
│   └── workflows/
│       ├── terraform-check.yml     # fmt + validate + tflint (PR trigger)
│       ├── terraform-plan.yml      # plan only (manual trigger)
│       ├── terraform-apply.yml     # apply (manual trigger)
│       ├── terraform-destroy.yml   # destroy with confirmation gate (manual trigger)
│       ├── ansible-check.yml       # lint + syntax check (PR trigger)
│       └── ansible-deploy.yml      # run playbook against VM (manual trigger)
├── terraform/
│   ├── env/
│   │   ├── dev/
│   │   │   ├── backend.tf          # S3 (MinIO) backend — empty config, filled at init
│   │   │   ├── providers.tf        # LXD provider + Terraform version constraints
│   │   │   ├── main.tf             # Calls the lxd-vm module
│   │   │   ├── variables.tf        # All input variables for this environment
│   │   │   ├── outputs.tf          # VM name, IP, MAC, SSH command
│   │   │   └── dev01.tfvars        # Per-VM resource config (committed, no secrets)
│   │   └── prod/
│   │       ├── backend.tf
│   │       ├── providers.tf
│   │       ├── main.tf             # Calls the lxd-vm module
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       └── prod01.tfvars
│   └── modules/
│       └── lxd-vm/
│           ├── main.tf             # lxd_instance resource + locals (instance name, cloud-init)
│           ├── variables.tf        # Module input variables
│           ├── outputs.tf          # vm_name, vm_ip, vm_mac_address, ansible_ssh_command
│           └── cloud-init/
│               └── user-data.yaml  # cloud-init template (ansible user, SSH hardening)
├── ansible/
│   ├── inventory.yml               # Dynamic inventory via VM_IP env var
│   ├── playbook.yml                # Entry playbook: common + docker roles
│   └── roles/
│       ├── common/
│       │   └── tasks/main.yml      # apt cache + base packages
│       └── docker/
│           └── tasks/main.yml      # Docker CE install from upstream repo
└── .gitignore
```

---

## Secrets & Variables

Configure all secrets at the **Gitea org level**: `Infra` → Settings → Secrets and Variables.

| Name | Type | Used By | Description |
|---|---|---|---|
| `LXD_ADDRESS` | Secret | Terraform | LXD API host (e.g. `192.168.x.x`) |
| `LXD_CLIENT_CERT` | Secret | Terraform | TLS client certificate (PEM) |
| `LXD_CLIENT_KEY` | Secret | Terraform | TLS client key (PEM) |
| `MINIO_ENDPOINT` | Secret | Terraform | MinIO S3 API URL |
| `MINIO_ACCESS_KEY` | Secret | Terraform | MinIO access key |
| `MINIO_SECRET_KEY` | Secret | Terraform | MinIO secret key |
| `ANSIBLE_SSH_PUBLIC_KEY` | Secret | Terraform | Injected into VM via cloud-init |
| `ANSIBLE_SSH_PRIVATE_KEY` | Secret | Ansible | Used by runner to SSH into VM |

---

## Workflows

### `terraform-check.yml` — Terraform Lint & Validate
**Trigger:** Pull Request or `workflow_dispatch`

Runs on every PR to catch issues before merge. Steps:
1. `terraform fmt -check -diff` — enforces canonical formatting across all `.tf` files
2. `terraform init -backend=false` — validates config without a real backend
3. `terraform validate` — checks HCL syntax and provider schema
4. `tflint` — additional lint rules

> No secrets required. Safe to run on any branch.

---

### `terraform-plan.yml` — Terraform Plan
**Trigger:** `workflow_dispatch`

Inputs:
| Input | Description | Example |
|---|---|---|
| `environment` | Must match env folder name | `dev` or `prod` |
| `vm_name` | Must match a `.tfvars` filename | `dev01`, `prod02` |

Steps:
1. Validates environment input (only `dev` / `prod` allowed)
2. Resolves `tfvars_file` and `state_key` paths from inputs
3. Writes LXD TLS certs to `~/.config/lxc/`
4. `terraform init` against MinIO backend, working in `terraform/env/<env>/`
5. `terraform plan` with the resolved `.tfvars` file

---

### `terraform-apply.yml` — Terraform Apply
**Trigger:** `workflow_dispatch`

Same inputs as Plan. Runs `terraform apply -auto-approve` after init. The workflow is scoped to a Gitea **environment** (matching the `environment` input), allowing environment-level protection rules and secret overrides.

VM name is constructed inside the `lxd-vm` module as: `<environment>-<os_type>-<vm_name>` (e.g. `prod-ubuntu-vm-prod02`).

---

### `terraform-destroy.yml` — Terraform Destroy
**Trigger:** `workflow_dispatch`

Inputs:
| Input | Description |
|---|---|
| `environment` | `dev` or `prod` |
| `vm_name` | VM to destroy |
| `confirm_destroy` | Must type `yes` — hard gate before destroy runs |

Includes a safety check step that prints the target VM and state path before proceeding.

---

### `ansible-check.yml` — Ansible Lint & Syntax Check
**Trigger:** Pull Request or `workflow_dispatch`

1. Installs Ansible and `ansible-lint` via `pipx`
2. Runs `ansible-lint ansible/playbook.yml`
3. Runs `ansible-playbook --syntax-check`

> No live VM required. Safe static analysis only.

---

### `ansible-deploy.yml` — Ansible Deploy
**Trigger:** `workflow_dispatch`

Inputs:
| Input | Description |
|---|---|
| `environment` | `dev` or `prod` |
| `vm_name` | Target VM name |

Steps:
1. Validates environment
2. Inits Terraform against MinIO to read existing state from `terraform/env/<env>/`
3. Reads VM IP from `terraform output -raw vm_ip`
4. Polls SSH port (up to 20 × 10s) until the VM is reachable
5. Writes `ANSIBLE_SSH_PRIVATE_KEY` to `~/.ssh/id_rsa`
6. Generates an inline `inventory.ini` targeting the VM
7. Runs `ansible/playbook.yml` with `ANSIBLE_HOST_KEY_CHECKING=False`

---

## Terraform: Resource Model

Each environment root module (`terraform/env/<env>/main.tf`) delegates all resource creation to the shared `lxd-vm` module:

```hcl
module "vm" {
  source = "../../modules/lxd-vm"

  vm_name                = var.vm_name
  os_type                = var.os_type
  environment            = var.environment
  ansible_ssh_public_key = var.ansible_ssh_public_key
  lxd_address            = var.lxd_address
  image                  = var.image
  network                = var.network
  storage_pool           = var.storage_pool
  disk_size              = var.disk_size
  cpu_count              = var.cpu_count
  memory_size            = var.memory_size
}
```

The `lxd-vm` module (`terraform/modules/lxd-vm/`) defines the `lxd_instance` resource, renders the cloud-init template, and exposes outputs (`vm_ip`, `vm_name`, `vm_mac_address`, `ansible_ssh_command`).

### VM Naming Convention

VM names are constructed inside the module's `locals` block:

```
<environment>-<os_type>-<vm_name>
```

Examples:
- `dev-ubuntu-vm-dev01`
- `prod-ubuntu-vm-prod02`

`os_type` and `vm_name` come from the `.tfvars` file; `environment` is injected via `TF_VAR_environment` from the workflow input.

### State Backend Path

State is stored in MinIO at:
```
s3://terraform-state/state/<environment>/<vm_name>/terraform.tfstate
```

Each VM gets its own isolated state file. The S3 backend is declared empty in `backend.tf` and fully configured at `terraform init` time via `-backend-config` flags in the workflow.

### cloud-init

The `cloud-init/user-data.yaml` template lives inside the `lxd-vm` module and is rendered by Terraform's `templatefile()`. It:
- Sets hostname to the full instance name
- Configures DHCP on `enp5s0` via netplan
- Creates an `ansible` user with SSH key auth and passwordless sudo
- Installs base packages (curl, wget, git, python3, openssh-server)
- Hardens SSH (disables password auth and root login)

### tfvars Files

Each VM has a dedicated `.tfvars` file under `terraform/env/<env>/`. Sensitive values (`lxd_address`, `ansible_ssh_public_key`) are **never** stored in tfvars — they are injected as `TF_VAR_*` environment variables from Gitea secrets.

Example (`dev01.tfvars`):
```hcl
image        = "ubuntu-24-04-vm"
os_type      = "ubuntu-vm"
network      = "lxdbr0"
storage_pool = "default"
disk_size    = "10GiB"
cpu_count    = 2
memory_size  = "2GiB"
```

---

## Ansible: Playbook & Roles

### Inventory

`ansible/inventory.yml` is dynamic — the VM IP is passed in via the `VM_IP` environment variable set by the `ansible-deploy` workflow after reading Terraform output:

```yaml
all:
  children:
    lxd_vms:
      hosts:
        target_vm:
          ansible_host: "{{ lookup('env', 'VM_IP') }}"
```

### Playbook

`ansible/playbook.yml` applies two roles in sequence:

| Role | Tags | What it does |
|---|---|---|
| `common` | `common` | Updates apt cache, installs base packages (curl, unzip, git, ca-certificates) |
| `docker` | `docker` | Adds Docker upstream repo + GPG key, installs docker-ce, enables the daemon |

### Roles

Both roles live locally under `ansible/roles/`. There is no external Galaxy dependency — all role tasks are self-contained.

**`common`** — idempotent base config, respects `cache_valid_time` to avoid redundant apt updates.

**`docker`** — installs Docker CE from `download.docker.com`. Uses `args: creates:` on the GPG key conversion step to ensure idempotency.

---

## End-to-End Deployment Flow

```
1. Create / edit a .tfvars file under terraform/env/<env>/
2. Open a PR → terraform-check + ansible-check run automatically
3. Merge to main
4. Manually trigger terraform-plan  →  review output
5. Manually trigger terraform-apply →  VM is created via LXD
   └─ lxd-vm module provisions the lxd_instance resource
   └─ cloud-init configures ansible user, SSH, base packages on first boot
6. Manually trigger ansible-deploy  →  Ansible roles applied to the live VM
   └─ common role: base packages
   └─ docker role: Docker CE installed and started
```

---

## Local Usage

```bash
# 1. Copy a tfvars example and fill in secrets locally
cp terraform/env/dev/dev01.tfvars terraform/env/dev/dev02.tfvars
# Add lxd_address and ansible_ssh_public_key as env vars

# 2. Init with MinIO backend (from the env directory)
cd terraform/env/dev
terraform init \
  -backend-config="endpoint=http://10.248.42.22:9000" \
  -backend-config="bucket=terraform-state" \
  -backend-config="key=state/dev/dev02/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="access_key=<key>" \
  -backend-config="secret_key=<secret>" \
  -backend-config="skip_credentials_validation=true" \
  -backend-config="skip_metadata_api_check=true" \
  -backend-config="skip_requesting_account_id=true" \
  -backend-config="force_path_style=true"

# 3. Export required TF_VAR_ secrets
export TF_VAR_lxd_address="<lxd-host-ip>"
export TF_VAR_ansible_ssh_public_key="ssh-ed25519 AAAA..."
export TF_VAR_environment="dev"
export TF_VAR_vm_name="dev02"

# 4. Plan and apply
terraform plan -var-file="dev02.tfvars"
terraform apply -var-file="dev02.tfvars"

# 5. Get SSH command
terraform output ansible_ssh_command

# 6. Run Ansible manually
VM_IP=$(terraform output -raw vm_ip)
ansible-playbook -i "$VM_IP," \
  -u ansible \
  --private-key ~/.ssh/id_ed25519 \
  ../../../ansible/playbook.yml
```

---

## Destroying a VM

Via Gitea UI: trigger `terraform-destroy.yml`, enter environment, VM name, and type `yes` to confirm.

Locally:
```bash
cd terraform/env/dev
terraform destroy -var-file="dev02.tfvars"
```

---

## Design Notes

This repo represents a **module-based iteration** of the homelab CI/CD stack — balancing reusability with simplicity:

- **Terraform `lxd-vm` module** — the LXD VM resource, cloud-init rendering, and outputs are encapsulated in `terraform/modules/lxd-vm/`. Each environment root module calls it with environment-specific inputs, keeping env configs thin and the VM logic in one place
- **No shared/reusable workflows** — each workflow is self-contained in this repo, so no cross-repo dependency to debug
- **No Ansible Galaxy** — roles are local, version-controlled here, no external registry required

When ready to scale, the natural evolution paths are:
- Host the `lxd-vm` module in a dedicated Gitea repo and reference it via `git::http://gitea.local/infra/terraform-lxd-vm.git`
- Move common workflows to a `shared-workflows` Gitea repo and call them via `workflow_call`
- Publish roles to a self-hosted Ansible Galaxy server and reference via `requirements.yml`
- Replace Gitea org secrets with OpenBao for dynamic, short-lived credentials

---
## Infrastructure Created and Maintained By

**Ali Ahmed**  
Building infrastructure, automation, and DevOps workflows  

**Contact**

[![GitHub](https://img.shields.io/badge/GitHub-%20Ali%20Ahmed-black?style=for-the-badge&logo=github)](https://github.com/jeffreyalie)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-%20Ali%20Ahmed-blue?style=for-the-badge&logo=linkedin)](https://www.linkedin.com/in/ali-ahmed-261755252/)
---
