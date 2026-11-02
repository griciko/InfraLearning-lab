terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}

provider "azuread" {
  tenant_id = var.tenant_id
}

data "azuread_application_published_app_ids" "well_known" {}

# Microsoft Graph's own service principal: read only, never destroyed by us
data "azuread_service_principal" "msgraph" {
  client_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]
}

locals {
  graph_roles = [
    "DeviceManagementConfiguration.ReadWrite.All",
    "DeviceManagementApps.ReadWrite.All",
    "DeviceManagementScripts.ReadWrite.All",
  ]
}

resource "azuread_application" "intune_tf" {
  display_name = "tf-app-intune-terraform"

  required_resource_access {
    resource_app_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]

    dynamic "resource_access" {
      for_each = local.graph_roles
      content {
        id   = data.azuread_service_principal.msgraph.app_role_ids[resource_access.value]
        type = "Role"
      }
    }
  }
}

resource "azuread_service_principal" "intune_tf" {
  client_id = azuread_application.intune_tf.client_id
}

# Admin consent, done as code
resource "azuread_app_role_assignment" "graph" {
  for_each            = toset(local.graph_roles)
  app_role_id         = data.azuread_service_principal.msgraph.app_role_ids[each.value]
  principal_object_id = azuread_service_principal.intune_tf.object_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}

# Short-lived secret, stored in the state file (same lesson as Day 2)
resource "azuread_service_principal_password" "intune_tf" {
  service_principal_id = azuread_service_principal.intune_tf.id
  end_date_relative    = "72h"
}