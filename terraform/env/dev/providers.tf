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
# LXD Provider (fully secret-driven)
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
