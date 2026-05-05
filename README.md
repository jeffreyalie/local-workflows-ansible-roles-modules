# Reusable Terraform + Ansible Infrastructure Workflows

This repository provides a comprehensive set of reusable Gitea Actions workflows for managing LXD-based Ubuntu VM infrastructure using Terraform and Ansible. The workflows support automated provisioning, configuration, and deployment across multiple environments.

## Summary

The repository implements a complete infrastructure-as-code solution that:
- **Provisions Ubuntu 24.04 VMs** on LXD using Terraform modules
- **Configures VMs** with cloud-init for automated setup
- **Deploys applications** via Ansible playbooks
- **Manages environments** (dev/prod) with separate state management
- **Provides CI/CD automation** through reusable Gitea Actions workflows

---

## Repository Structure

```
.
├── .gitea/workflows/                    # Reusable CI/CD workflows
│   ├── reusable-terraform-check.yml    # Terraform validation
│   ├── reusable-terraform-plan.yml      # Infrastructure planning
│   ├── reusable-terraform-apply.yml    # Infrastructure deployment
│   ├── reusable-terraform-destroy.yml   # Infrastructure cleanup
│   ├── reusable-ansible-check.yml       # Ansible validation
│   └── reusable-ansible-deploy.yml      # Application deployment
├── terraform/                          # Infrastructure code
│   ├── modules/                        # Reusable Terraform modules
│   │   └── lxd-vm/                     # LXD VM provisioning module
│   │       ├── main.tf                 # VM resource definitions
│   │       ├── variables.tf            # Module variables
│   │       ├── outputs.tf              # Module outputs
│   │       └── cloud-init/             # VM initialization scripts
│   │           └── user-data.yaml     # cloud-init template
│   └── env/                           # Environment-specific configurations
│       ├── dev/                       # Development environment
│       │   ├── dev01.tfvars          # Dev VM configuration
│       │   ├── main.tf               # Dev environment resources
│       │   ├── providers.tf          # LXD provider configuration
│       │   ├── variables.tf          # Dev environment variables
│       │   └── outputs.tf            # Dev environment outputs
│       └── prod/                      # Production environment
│           ├── prod01.tfvars         # Prod VM configuration
│           ├── main.tf               # Prod environment resources
│           ├── providers.tf          # LXD provider configuration
│           ├── variables.tf          # Prod environment variables
│           └── outputs.tf            # Prod environment outputs
├── ansible/                           # Configuration management
│   ├── playbook.yml                   # Main Ansible playbook
│   ├── inventory.yml                  # Dynamic inventory (generated)
│   └── roles/                        # Ansible role definitions
│       ├── common/                   # Common system configuration
│       │   └── tasks/
│       │       └── main.yml          # Common package installation
│       └── docker/                   # Docker installation and configuration
│           └── tasks/
│               └── main.yml          # Docker setup tasks
└── reusable-workflow-client-repo/    # Usage examples
```

---

## Module Structure & Functionality

### LXD VM Module (`terraform/modules/lxd-vm/`)

#### Core Components:
- **`main.tf`**: Defines LXD instance with cloud-init configuration
- **`variables.tf`**: Module input parameters
- **`outputs.tf`**: VM connection and configuration outputs
- **`cloud-init/user-data.yaml`**: Automated VM initialization

#### Key Features:
- **Dynamic VM naming**: `{environment}-{os_type}-{vm_name}` (e.g., `dev-ubuntu-dev01`)
- **Cloud-init automation**: Sets up SSH access, users, packages, and networking
- **Network configuration**: DHCP on primary interface with proper routing
- **SSH hardening**: Password authentication disabled, root login disabled
- **Resource management**: CPU, memory, and disk allocation

#### Required Variables:
```terraform
# LXD Configuration
variable "lxd_address" {
  description = "LXD server address"
  type        = string
}

# VM Configuration
variable "vm_name" {
  description = "VM identifier (e.g., dev01)"
  type        = string
}

variable "environment" {
  description = "Environment (dev/prod)"
  type        = string
}

variable "os_type" {
  type        = string
}

variable "storage_pool" {
  description = "LXD storage pool name"
  type        = string
}

variable "disk_size" {
  description = "Disk size (e.g., 20GB)"
  type        = string
}

variable "cpu_count" {
  description = "Number of CPUs"
  type        = number
}

variable "memory_size" {
  description = "Memory size (e.g., 2GB)"
  type        = string
}

# SSH Configuration
variable "ansible_ssh_public_key" {
  description = "SSH public key for ansible user"
  type        = string
}
```

#### Outputs:
```terraform
output "vm_name" {
  description = "Name of the deployed VM"
  value       = lxd_instance.ubuntu_vm.name
}

output "vm_ip" {
  description = "IP address of the VM"
  value       = lxd_instance.ubuntu_vm.ipv4_address
}

output "ansible_ssh_command" {
  description = "SSH command to connect to the VM"
  value       = "ssh ansible@${lxd_instance.ubuntu_vm.ipv4_address}"
}
```

---

## Ansible Workflow Integration

### Ansible Roles Structure:
- **`common` role**: Installs essential packages (curl, git, python3, etc.)
- **`docker` role**: Installs Docker CE and configures the service

### Workflow Integration:
The `reusable-ansible-deploy.yml` workflow:
1. **Retrieves VM IP** from Terraform state
2. **Creates dynamic inventory** for Ansible
3. **Waits for SSH connectivity** 
4. **Deploys applications** using the defined playbook

### Key Ansible Features:
- **Dynamic inventory generation** based on Terraform outputs
- **SSH key-based authentication** with passwordless sudo
- **Package management** via apt with caching
- **Docker installation** from official repositories

---

## Required Secrets & Configuration

### Gitea Repository Secrets:

| Secret Name | Description | Required For |
|-------------|-------------|--------------|
| `MINIO_ENDPOINT` | MinIO S3 endpoint for Terraform state | All Terraform workflows |
| `MINIO_ACCESS_KEY` | MinIO access key | All Terraform workflows |
| `MINIO_SECRET_KEY` | MinIO secret key | All Terraform workflows |
| `LXD_ADDRESS` | LXD server address | All Terraform workflows |
| `ANSIBLE_SSH_PUBLIC_KEY` | SSH public key for VM access | All workflows |
| `ANSIBLE_SSH_PRIVATE_KEY` | SSH private key for deployment | Ansible Deploy |
| `LXD_TRUST_PASSWORD` | LXD trust password | Terraform workflows |
| `LXD_CLIENT_CERT` | LXD client certificate (optional) | Terraform Apply/Destroy |
| `LXD_CLIENT_KEY` | LXD client private key (optional) | Terraform Apply/Destroy |

### Environment Configuration:

#### Development Environment (`terraform/env/dev/dev01.tfvars`):
```tfvars
environment = "dev"
vm_name = "dev01"
os_type = "ubuntu"
storage_pool = "default"
disk_size = "20GB"
cpu_count = 2
memory_size = "2GB"
```

#### Production Environment (`terraform/env/prod/prod01.tfvars`):
```tfvars
environment = "prod"
vm_name = "prod01"
os_type = "ubuntu"
storage_pool = "default"
disk_size = "40GB"
cpu_count = 4
memory_size = "4GB"
```

---

## How to Use the Workflows

### 1. Terraform Workflows

#### Basic Usage:
```yaml
name: "Terraform Plan"
on:
  workflow_dispatch:
    inputs:
      environment:
        description: "Environment (dev/prod)"
        required: true
        type: string
      vm_name:
        description: "VM name (e.g., dev01, prod01)"
        required: true

jobs:
  plan:
    uses: <owner>/<repo>/.gitea/workflows/reusable-terraform-plan.yml@main
    with:
      environment: ${{ github.event.inputs.environment }}
      vm_name: ${{ github.event.inputs.vm_name }}
    secrets:
      MINIO_ENDPOINT: ${{ secrets.MINIO_ENDPOINT }}
      MINIO_ACCESS_KEY: ${{ secrets.MINIO_ACCESS_KEY }}
      MINIO_SECRET_KEY: ${{ secrets.MINIO_SECRET_KEY }}
      LXD_ADDRESS: ${{ secrets.LXD_ADDRESS }}
      ANSIBLE_SSH_PUBLIC_KEY: ${{ secrets.ANSIBLE_SSH_PUBLIC_KEY }}
      LXD_TRUST_PASSWORD: ${{ secrets.LXD_TRUST_PASSWORD }}
```

#### Workflow Features:
- **Environment validation**: Only allows "dev" or "prod"
- **tfvars file validation**: Ensures configuration files exist
- **Terraform validation**: Format, init, and validate checks
- **State management**: MinIO backend for remote state storage

### 2. Ansible Workflows

#### Basic Usage:
```yaml
name: "Ansible Deploy"
on:
  workflow_dispatch:
    inputs:
      environment:
        description: "Environment (dev/prod)"
        required: true
      vm_name:
        description: "VM name (e.g., dev01, prod01)"
        required: true

jobs:
  deploy:
    uses: <owner>/<repo>/.gitea/workflows/reusable-ansible-deploy.yml@main
    with:
      environment: ${{ github.event.inputs.environment }}
      vm_name: ${{ github.event.inputs.vm_name }}
      ansible_playbook_path: "ansible/playbook.yml"
    secrets:
      MINIO_ENDPOINT: ${{ secrets.MINIO_ENDPOINT }}
      MINIO_ACCESS_KEY: ${{ secrets.MINIO_ACCESS_KEY }}
      MINIO_SECRET_KEY: ${{ secrets.MINIO_SECRET_KEY }}
      LXD_ADDRESS: ${{ secrets.LXD_ADDRESS }}
      ANSIBLE_SSH_PUBLIC_KEY: ${{ secrets.ANSIBLE_SSH_PUBLIC_KEY }}
      ANSIBLE_SSH_PRIVATE_KEY: ${{ secrets.ANSIBLE_SSH_PRIVATE_KEY }}
```

#### Workflow Features:
- **Terraform integration**: Retrieves VM IP from Terraform state
- **SSH connectivity**: Waits for SSH to be ready before deployment
- **Dynamic inventory**: Creates inventory file based on VM IP
- **Error handling**: Validates playbook syntax before execution

---

## Workflow Usage Examples

Complete examples are available in the `reusable-workflow-client-repo/` directory:

### Example Workflow Files:
- **`terraform-check.yml`**: PR validation for Terraform code
- **`terraform-plan.yml`**: Infrastructure planning
- **`terraform-apply.yml`**: Infrastructure deployment
- **`terraform-destroy.yml`**: Infrastructure cleanup
- **`ansible-check.yml`**: Ansible playbook validation
- **`ansible-deploy.yml`**: Application deployment

### Key Workflow Behaviors:
- **PR triggers**: Automatic validation on pull requests
- **Manual triggers**: On-demand workflow execution
- **Environment separation**: Separate state and configurations for dev/prod
- **Safety checks**: Confirmation required for destructive operations

---

## Cloud-init Configuration

The `user-data.yaml` template provides:
- **Network setup**: DHCP configuration with proper routing
- **User creation**: `ansible` user with SSH access and sudo privileges
- **Package installation**: Essential tools and Python packages
- **SSH hardening**: Disabled password authentication, no root login
- **Service configuration**: Automatic service restarts and logging

---

## Security Considerations

### SSH Configuration:
- **Key-based authentication only**
- **Password authentication disabled**
- **Root login disabled**
- **Sudo access without password** for automation

### Network Security:
- **DHCP networking** with static route metrics
- **Firewall rules** applied via cloud-init
- **Network isolation** through LXD bridge networking

### Access Control:
- **Separate environments** with isolated configurations
- **Secret management** through Gitea repository secrets
- **State separation** via MinIO backend configuration

---

## Troubleshooting

### Common Issues:

**Terraform init failures**
- Verify MinIO credentials and endpoint
- Ensure MinIO bucket "terraform-state" exists
- Check network connectivity to MinIO server

**Ansible deployment failures**
- Verify SSH keys are correct and have proper permissions
- Ensure VM IP is accessible from runner
- Check Ansible playbook syntax with the check workflow first

**VM provisioning issues**
- Verify LXD server address and connectivity
- Check LXD storage pool availability
- Ensure cloud-init template syntax is correct

---

## Support

For issues or questions, refer to the workflow implementations in `.gitea/workflows/` or contact the repository maintainer. Complete usage examples are available in the `reusable-workflow-client-repo/` directory.

---

## 👨‍💻 Maintained by

**Ali Ahmed**  
Building infrastructure, automation, and DevOps workflows  

[![GitHub](https://img.shields.io/badge/GitHub-aliahmed-black?style=for-the-badge&logo=github)](https://github.com/jeffreyalie)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-aliahmed-blue?style=for-the-badge&logo=linkedin)](https://www.linkedin.com/in/ali-ahmed-261755252/)

---

## 💬 Contact

Have questions, ideas, or want to collaborate?

- Open an issue  
- Or connect with me on LinkedIn  

---

## 📄 License

This project is licensed under the MIT License.

---
