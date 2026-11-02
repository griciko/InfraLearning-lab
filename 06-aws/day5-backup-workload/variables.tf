# ---------- Region to deploy into ----------
variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-north-1"
}

# ---------- My public IP, for the SSH rule ----------
variable "my_ip" {
  description = "85.145.241.192"
  type        = string
}

# ---------- EC2 key pair name (as shown in the AWS console) ----------
variable "key_name" {
  description = "terransikey"
  type        = string
}

# ---------- Path of the private key, as seen from WSL (used by Ansible) ----------
variable "ssh_key_path" {
  description = ".ssh/terransikey.pem"
  type        = string
}

# ---------- Tag value that opts the data volume into the daily backup ----------
variable "backup_tag_value" {
  description = "tagged-backup-daily"
  type        = string
  default     = "daily"
}

# ---------- Availability zone for the instance (needed so the restored volume can attach) ----------
variable "availability_zone" {
  description = "AZ to start the instance in. Leave null to let AWS choose"
  type        = string
  default     = null
}

# ---------- ID of an existing (restored) volume. Empty = create a new volume ----------
variable "restored_volume_id" {
  description = "Volume ID created by a restore job. Empty means create a new empty volume"
  type        = string
  default     = ""
}