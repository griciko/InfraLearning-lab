terraform {
  required_providers {
    microsoft365 = {
      source  = "deploymenttheory/microsoft365"
      version = "~> 1.5.0"
    }
  }
}

provider "microsoft365" {
  cloud       = "public"
  tenant_id   = var.tenant_id
  auth_method = "client_secret"

  entra_id_options = {
    client_id     = var.client_id
    client_secret = var.client_secret
  }
}