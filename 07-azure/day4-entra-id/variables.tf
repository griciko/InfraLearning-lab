variable "subscription_id" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "usage_location" {
  type        = string
  description = "Two-letter country code for the test users"
}

variable "location" {
  type    = string
  default = "belgiumcentral"
}
