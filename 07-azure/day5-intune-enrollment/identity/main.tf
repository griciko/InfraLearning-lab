terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azuread" {
  tenant_id = var.tenant_id
}

data "azuread_domains" "initial" {
  only_initial = true
}

locals {
  upn_domain = data.azuread_domains.initial.domains[0].domain_name
}

# Generated password. It will be stored in the state file (same lesson as Day 2).
resource "random_password" "user" {
  length      = 20
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

resource "azuread_user" "intune" {
  user_principal_name   = "tf.intune01@${local.upn_domain}"
  display_name          = "TF Intune01"
  mail_nickname         = "tf.intune01"
  password              = random_password.user.result
  force_password_change = false
  usage_location        = var.usage_location
}

resource "azuread_group" "intune_test" {
  display_name     = "grp-tf-intune-test"
  description      = "Test group for the Intune labs (Terraform)"
  security_enabled = true
}

resource "azuread_group_member" "intune" {
  group_object_id  = azuread_group.intune_test.object_id
  member_object_id = azuread_user.intune.object_id
}