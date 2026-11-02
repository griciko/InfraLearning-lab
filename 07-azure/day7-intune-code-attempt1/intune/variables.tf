variable "tenant_id" {
  type = string
}

variable "subscription_id" {
  type        = string
  description = "Not used in this project, kept so the shared tfvars file loads without a warning"
}

variable "usage_location" {
  type        = string
  description = "Not used in this project, kept so the shared tfvars file loads without a warning"
}

variable "client_id" {
  type = string
}

variable "client_secret" {
  type      = string
  sensitive = true
}

variable "ring_id" {
  type = string
}

variable "test_group_id" {
  type = string
}

variable "profile_id" {
  type = string
}

variable "script_id" {
  type = string
}
