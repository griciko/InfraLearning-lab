output "user_principal_names" {
  value = { for k, u in azuread_user.lab : k => u.user_principal_name }
}

output "initial_passwords" {
  value     = { for k, p in random_password.user : k => p.result }
  sensitive = true
}
