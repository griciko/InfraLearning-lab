variable "subscription_id" {
  type = string
}

variable "location" {
  type    = string
  default = "belgiumcentral"
}

variable "my_ip" {
  type = string
}

variable "vm_size" {
  type    = string
  default = "Standard_B2ats_v2"
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/azure_lab.pub"
}

# Empty = new empty disk. Set it to a snapshot ID to restore the data disk from that snapshot.
variable "restore_snapshot_id" {
  type    = string
  default = ""
}