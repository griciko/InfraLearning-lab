# ---------- Terraform, provider versions and remote state ----------
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  # State goes in the Day 3 bucket, under its own key: a different state from the platform project
  backend "s3" {
    bucket       = "tfstate-365957109875-eu-north-1"
    key          = "day5-backup-workload/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}

# ---------- AWS provider ----------
provider "aws" {
  region = var.region
}