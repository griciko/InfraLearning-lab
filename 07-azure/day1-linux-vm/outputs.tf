output "public_ip" {
  value = azurerm_public_ip.lab.ip_address
}

output "ssh_command" {
  value = "ssh -i ~/.ssh/azure_lab azureuser@${azurerm_public_ip.lab.ip_address}"
}