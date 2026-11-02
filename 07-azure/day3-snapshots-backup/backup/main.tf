terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {
    recovery_service {
      vm_backup_stop_protection_and_retain_data_on_destroy = false
      purge_protected_items_from_vault_on_destroy          = true
    }
  }
  subscription_id = var.subscription_id
}

locals {
  tags = {
    project = "infra-learning-lab"
    day     = "03"
  }
}

resource "azurerm_resource_group" "backup" {
  name     = "rg-tf-backup-day03"
  location = var.location
  tags     = local.tags
}

resource "azurerm_recovery_services_vault" "lab" {
  name                = "rsv-lab-day03"
  location            = azurerm_resource_group.backup.location
  resource_group_name = azurerm_resource_group.backup.name
  sku                 = "Standard"
  storage_mode_type   = "LocallyRedundant"
  tags                = local.tags
}

# RPO 24 hours: a daily backup. 7 daily recovery points are kept.
resource "azurerm_backup_policy_vm" "daily" {
  name                = "policy-daily-7d"
  resource_group_name = azurerm_resource_group.backup.name
  recovery_vault_name = azurerm_recovery_services_vault.lab.name
  timezone            = "UTC"

  backup {
    frequency = "Daily"
    time      = "23:00"
  }

  retention_daily {
    count = 7
  }
}

# The workload belongs to another project: it is only read here
data "azurerm_virtual_machine" "workload" {
  name                = "vm-tf-lab-03"
  resource_group_name = "rg-tf-lab-day03"
}

resource "azurerm_backup_protected_vm" "workload" {
  resource_group_name = azurerm_resource_group.backup.name
  recovery_vault_name = azurerm_recovery_services_vault.lab.name
  source_vm_id        = data.azurerm_virtual_machine.workload.id
  backup_policy_id    = azurerm_backup_policy_vm.daily.id
}