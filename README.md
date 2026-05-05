# infrastructure-automation

GitOps pipeline for provisioning and configuring LXD virtual machines using Terraform and Ansible, orchestrated through Gitea Actions with MinIO as the Terraform state backend.

---

## Stack Overview

| Component | Role | Homelab equivalent of |
|---|---|---|
| **Gitea Actions** | CI/CD orchestration | GitHub Actions |
| **LXD / KVM** | VM hypervisor | AWS EC2 |
| **Terraform** | VM provisioning (LXD provider v2) | Terraform Cloud |
| **MinIO** | Terraform state backend (S3-compatible) | AWS S3 |
| **Ansible** | Post-provisioning VM configuration | Ansible Tower |
| **cloud-init** | First-boot VM setup (users, SSH, packages) | EC2 user data |

---

## Repository Structure

```
.
├── .gitea/
│   └── workflows/
│       ├── terraform-check.yml      # Lint + validate on PR
│       ├── terraform-plan.yml       # Manual plan (workflow_dispatch)
│       ├── terraform-apply.yml      # Manual apply (workflow_dispatch)
│       ├── terraform-destroy.yml    # Manual destroy with confirmation gate
│       ├── ansible-check.yml        # Ansible lint + syntax check on PR
│       └── ansible-deploy.yml       # Run Ansible against a live VM
├── ansible/
│   ├── inventory.yml                # Dynamic inventory (VM_IP from env)
│   ├── playbook.yml                 # Entry playbook (common + docker roles)
│   └── roles/
│       ├── common/tasks/main.yml    # Base packages (curl, git, ca-certs…)
│       └── docker/tasks/main.yml    # Docker CE install + service enable
└── terraform/
    ├── env/
    │   ├── dev/
    │   │   ├── backend.tf           # S3 (MinIO) backend — no values here
    │   │   ├── providers.tf         # LXD provider (TLS cert auth)
    │   │   ├── main.tf              # Calls lxd-vm module
    │   │   ├── variables.tf
    │   │   ├── outputs.tf
    │   │   └── dev01.tfvars         # Per-VM configuration
    │   └── prod/
    │       ├── backend.tf
    │       ├── providers.tf
    │       ├── main.tf
    │       ├── variables.tf
    │       ├── outputs.tf
    │       └── prod01.tfvars
    └── modules/
        └── lxd-vm/
            ├── main.tf              # lxd_instance resource + cloud-init render
            ├── variables.tf
            ├── outputs.tf
            └── cloud-init/
                └── user-data.yaml   # Ansible user, SSH hardening, packages
```

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Ubuntu 24.04 host | With LXD installed via snap |
| Gitea + Gitea Actions runner | Runner registered to the `Infra` org |
| LXD cached image | `ubuntu-24-04-vm` — imported via `lxc image copy` |
| MinIO instance | Bucket `terraform-state` created, credentials ready |
| Terraform ≥ 1.5 | Installed on the runner |
| LXD TLS client certificate | Generated and trusted on the LXD host |

---

## Secrets & Variables

Configure all secrets under **Gitea → Infra org → Settings → Secrets and Variables**.

| Secret | Description |
|---|---|
| `LXD_ADDRESS` | LXD API hostname or IP (without `https://` or port) |
| `LXD_CLIENT_CERT` | Contents of the runner's LXD client certificate (`.crt`) |
| `LXD_CLIENT_KEY` | Contents of the runner's LXD client private key (`.key`) |
| `ANSIBLE_SSH_PUBLIC_KEY` | Public key injected into VMs for the `ansible` user |
| `ANSIBLE_SSH_PRIVATE_KEY` | Private key used by the runner to SSH into VMs |
| `MINIO_ENDPOINT` | MinIO S3 API endpoint (e.g. `http://10.x.x.x:9000`) |
| `MINIO_ACCESS_KEY` | MinIO access key |
| `MINIO_SECRET_KEY` | MinIO secret key |

> **LXD certificate setup** — the runner writes the cert/key pair to `~/.config/lxc/`
> at job start. The LXD provider picks them up automatically.

---

## VM Naming Convention

VM names are composed automatically inside the `lxd-vm` module:

```
<environment>-<os_type>-<vm_name>
```

Example: inputs `environment=prod`, `os_type=ubuntu-vm`, `vm_name=prod01`
produce the LXD instance name **`prod-ubuntu-vm-prod01`**.

The `vm_name` input must match the `.tfvars` filename:

```
terraform/env/prod/prod01.tfvars  →  vm_name input = prod01
```

---

## Workflows

### `terraform-check` — runs on Pull Request

Validates all Terraform code before merging. No backend connection required.

Steps: `fmt -check` → `init -backend=false` → `validate` → `tflint`

---

### `terraform-plan` — manual (`workflow_dispatch`)

Runs a full `terraform plan` against a live environment and real MinIO state.

**Inputs:**

| Input | Example | Description |
|---|---|---|
| `environment` | `dev` or `prod` | Must match folder under `terraform/env/` |
| `vm_name` | `dev01` | Must match a `.tfvars` file in that env folder |

**Steps:** checkout → validate inputs → validate tfvars exists → setup TF → write LXD certs → `terraform init` (MinIO) → `terraform validate` → `terraform plan -var-file=<vm>.tfvars`

---

### `terraform-apply` — manual (`workflow_dispatch`)

Provisions or updates a VM. Runs the same steps as plan, then `apply -auto-approve`.

**Inputs:** same as `terraform-plan`.

> Run `terraform-plan` first to review the diff before applying.

---

### `terraform-destroy` — manual (`workflow_dispatch`)

Destroys a VM. Includes a hard confirmation gate.

**Inputs:**

| Input | Description |
|---|---|
| `environment` | `dev` or `prod` |
| `vm_name` | VM to destroy |
| `confirm_destroy` | Must be exactly `yes` — any other value aborts the job |

---

### `ansible-check` — runs on Pull Request

Lints and syntax-checks all Ansible code before merging. No live VM required.

Steps: install `ansible` + `ansible-lint` via pipx → `ansible-lint playbook.yml` → `ansible-playbook --syntax-check`

---

### `ansible-deploy` — manual (`workflow_dispatch`)

Runs the Ansible playbook against a VM that has already been provisioned by Terraform. Reads the VM IP directly from Terraform state via `terraform output`.

**Inputs:**

| Input | Description |
|---|---|
| `environment` | `dev` or `prod` |
| `vm_name` | Must match the provisioned VM |

**Steps:** checkout → validate env → install Ansible → init Terraform (to read state) → `terraform output -raw vm_ip` → wait for SSH (20 × 10 s) → write SSH private key → build inventory → `ansible-playbook`

---

## Terraform State

State is stored per VM in MinIO under:

```
terraform-state/state/<environment>/<vm_name>/terraform.tfstate
```

Example: `terraform-state/state/prod/prod01/terraform.tfstate`

The `backend "s3" {}` block in each env's `backend.tf` is intentionally empty — all
backend config is passed at `init` time via `-backend-config` flags in the workflow,
which reads values from org-level secrets.

Required MinIO flags (always set in `terraform init`):

```
skip_credentials_validation = true
skip_metadata_api_check     = true
skip_requesting_account_id  = true
force_path_style            = true
```

---

## Ansible Roles

The playbook applies two roles in order, both requiring `become: true`.

### `common`
Installs base packages: `curl`, `unzip`, `git`, `ca-certificates`.
Uses `cache_valid_time: 3600` to avoid redundant apt updates.

### `docker`
Installs Docker CE from the official Docker apt repo:
1. Adds the Docker GPG key to `/etc/apt/keyrings/`
2. Adds the Docker apt repository (Ubuntu `jammy`)
3. Installs `docker-ce`, `docker-ce-cli`, `containerd.io`
4. Enables and starts the `docker` systemd service

---

## cloud-init Details

The `lxd-vm` module renders `cloud-init/user-data.yaml` as a Terraform template,
injecting the `ansible_ssh_public_key` and the computed `vm_hostname`.

On first boot the VM will:

- Set hostname and FQDN to the full instance name
- Configure DHCP on `enp5s0` via netplan
- Create an `ansible` user with passwordless sudo and SSH key-only auth
- Install: `curl`, `wget`, `git`, `python3`, `python3-pip`, `openssh-server`, `net-tools`
- Write `/etc/ssh/sshd_config.d/99-ansible.conf` (disables password + root login)
- Restart `sshd`

---

## Adding a New VM

1. Create a `.tfvars` file under the correct environment folder:

```bash
cp terraform/env/dev/dev01.tfvars terraform/env/dev/dev02.tfvars
# Edit dev02.tfvars — adjust cpu_count, memory_size, disk_size as needed
```

2. Commit and push to Gitea. Open a PR to trigger `terraform-check` and `ansible-check`.

3. After merging, run **Terraform Plan** from Gitea Actions → select `dev` / `dev02`.

4. Review the plan output, then run **Terraform Apply**.

5. Once the VM is up, run **Ansible Deploy** with the same inputs to configure it.

---

## Local Usage

```bash
cd terraform/env/dev

# Initialise with MinIO backend
terraform init \
  -backend-config="endpoint=http://<minio-ip>:9000" \
  -backend-config="bucket=terraform-state" \
  -backend-config="key=state/dev/dev01/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="access_key=<key>" \
  -backend-config="secret_key=<secret>" \
  -backend-config="skip_credentials_validation=true" \
  -backend-config="skip_metadata_api_check=true" \
  -backend-config="skip_requesting_account_id=true" \
  -backend-config="force_path_style=true"

# Plan
TF_VAR_lxd_address=<lxd-ip> \
TF_VAR_ansible_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)" \
TF_VAR_environment=dev \
TF_VAR_vm_name=dev01 \
terraform plan -var-file="dev01.tfvars"

# Apply
terraform apply -auto-approve -var-file="dev01.tfvars"

# Get SSH command
terraform output ansible_ssh_command
```

---

## Roadmap

| Feature | Status | Notes |
|---|---|---|
| **OpenBao** | Planned | Replace org-level secrets with a Vault-compatible secrets manager |
| **Reusable GHA Workflows** | Planned | Centralise plan/apply/destroy into a shared `infra/shared-workflows` repo |
| **Reusable Terraform Modules** | Planned | Publish `lxd-vm` module to a dedicated Gitea repo, consume via `git::http://` |
| **Ansible Galaxy (self-hosted)** | Planned | Host roles on Gitea, reference in `requirements.yml` |
| **oVirt integration** | Exploring | More enterprise-equivalent VM target alongside LXD |
| **MicroK8s app pipeline** | Planned | Docker + Helm deployment track for Go workloads |
