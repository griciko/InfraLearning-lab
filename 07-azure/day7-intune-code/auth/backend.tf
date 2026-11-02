terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stlabtfstate60686"
    container_name       = "tfstate"
    key                  = "day7-intune-auth.tfstate"
    use_azuread_auth     = true
  }
}
