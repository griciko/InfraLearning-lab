variable "subscription_id" {
  type        = string
  description = "Not used in this project, kept so the shared tfvars file loads without a warning"
}

variable "tenant_id" {
  type = string
}

variable "usage_location" {
  type        = string
  description = "Two-letter country code, needed before a license can be assigned"
}