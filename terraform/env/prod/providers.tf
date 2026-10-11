# ---------------------------------------------------------------------------
# Terraform Configuration for LXD Provider
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    lxd = {
      source  = "terraform-lxd/lxd"
      version = "~> 2.0"
    }
  }

}

# ---------------------------------------------------------------------------
# LXD Provider - will pick up certificate files from ~/.config/lxc/ for authentication defined in workflow secrets LXD_CLIENT_CERT and LXD_CLIENT_KEY
# ---------------------------------------------------------------------------
provider "lxd" {
  accept_remote_certificate    = true
  generate_client_certificates = true

  remote {
    name     = "lxd-host"
    address  = "https://${var.lxd_address}:8443"
    default  = true
    # password = var.lxd_trust_password
  }
}
