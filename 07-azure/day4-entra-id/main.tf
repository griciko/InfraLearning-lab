terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
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

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# The tenant's *.onmicrosoft.com domain, used for the user names
data "azuread_domains" "initial" {
  only_initial = true
}

locals {
  domain = data.azuread_domains.initial.domains[0].domain_name

  tags = {
    project = "infra-learning-lab"
    day     = "04"
  }

  groups = {
    readers   = { name = "grp-tf-readers", description = "Terraform test: read-only on the Day 4 resource group" }
    operators = { name = "grp-tf-operators", description = "Terraform test: contributor on the Day 4 resource group" }
  }

  users = {
    reader   = { display = "TF Reader", nick = "tf.reader", group = "readers" }
    operator = { display = "TF Operator", nick = "tf.operator", group = "operators" }
  }
}

# Generated passwords. They end up in the state file (same lesson as Day 2).
resource "random_password" "user" {
  for_each    = local.users
  length      = 20
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

resource "azuread_user" "lab" {
  for_each = local.users

  user_principal_name   = "${each.value.nick}@${local.domain}"
  display_name          = each.value.display
  mail_nickname         = each.value.nick
  password              = random_password.user[each.key].result
  force_password_change = false # lab shortcut, see production note
  usage_location        = var.usage_location
  account_enabled       = true
}

resource "azuread_group" "lab" {
  for_each = local.groups

  display_name     = each.value.name
  description      = each.value.description
  security_enabled = true
  mail_enabled     = false
}

resource "azuread_group_member" "lab" {
  for_each = local.users

  group_object_id  = azuread_group.lab[each.value.group].object_id
  member_object_id = azuread_user.lab[each.key].object_id
}

# A resource group only to hold the permissions test
resource "azurerm_resource_group" "rbac" {
  name     = "rg-tf-lab-day04"
  location = var.location
  tags     = local.tags
}

resource "azurerm_role_assignment" "readers" {
  scope                = azurerm_resource_group.rbac.id
  role_definition_name = "Reader"
  principal_id         = azuread_group.lab["readers"].object_id
  principal_type       = "Group"
}

resource "azurerm_role_assignment" "operators" {
  scope                = azurerm_resource_group.rbac.id
  role_definition_name = "Contributor"
  principal_id         = azuread_group.lab["operators"].object_id
  principal_type       = "Group"
}
