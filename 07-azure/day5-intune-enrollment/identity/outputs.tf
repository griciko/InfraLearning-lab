output "user_upn" {
  value = azuread_user.intune.user_principal_name
}

output "user_password" {
  value     = random_password.user.result
  sensitive = true
}