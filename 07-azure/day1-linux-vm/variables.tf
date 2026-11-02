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
  default = "Standard_B2ats_v2"
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/azure_lab.pub"
}