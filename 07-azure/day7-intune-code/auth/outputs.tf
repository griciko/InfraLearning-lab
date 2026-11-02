output "client_id" {
  value = azuread_application.intune_tf.client_id
}

output "client_secret" {
  value     = azuread_service_principal_password.intune_tf.value
  sensitive = true
}