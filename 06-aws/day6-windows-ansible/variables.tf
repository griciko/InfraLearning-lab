# ---------- Region to deploy into ----------
variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-north-1"
}

# ---------- My public IP, for the security group rules ----------
variable "my_ip" {
  description = "My public IP address, without /32"
  type        = string
}

# ---------- Name of the RSA key pair used for Windows (as shown in the AWS console) ----------
variable "key_name" {
  description = "Name of the RSA EC2 key pair for Windows"
  type        = string
}

# ---------- Instance type: use the one that worked on Day 3 ----------
variable "instance_type" {
  description = "EC2 instance type allowed on this account"
  type        = string
  default     = "c7i-flex.large"
}