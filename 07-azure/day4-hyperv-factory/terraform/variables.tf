variable "hyperv_host" {
  type = string
}

variable "switch_name" {
  type = string
}

variable "parent_vhdx" {
  type    = string
  default = "D:\\HypVMs\\tf-images\\win11-base.vhdx"
}

variable "vm_root" {
  type    = string
  default = "D:\\HypVMs\\tf-vms"
}
