output "public_ip" {
  value = azurerm_public_ip.lab.ip_address
}

output "admin_username" {
  value = "azureadmin"
}

output "admin_password" {
  value     = random_password.admin.result
  sensitive = true
}

output "rdp_command" {
  value = "mstsc /v:${azurerm_public_ip.lab.ip_address}"
}