# ---------- Region to deploy into ----------
variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-north-1"
}

# ---------- Name of the backup vault ----------
variable "vault_name" {
  description = "Name of the backup vault"
  type        = string
  default     = "lab-vault"
}

# ---------- How long scheduled recovery points are kept ----------
variable "retention_days" {
  description = "Days to keep scheduled recovery points"
  type        = number
  default     = 7
}

# ---------- Tag value that opts a resource into the daily backup ----------
variable "backup_tag_value" {
  description = "Resources tagged backup = <this value> are backed up by the plan"
  type        = string
  default     = "daily"
}