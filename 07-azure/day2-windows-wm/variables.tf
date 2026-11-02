variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "location" {
  type    = string
  default = "belgiumcentral"
}

variable "my_ip" {
  type        = string
  description = "My public IP with /32"
}

variable "vm_size" {
  type    = string
  default = "Standard_B2s_v2"
}

variable "windows_sku" {
  type    = string
  default = "2025-datacenter-azure-edition"
}