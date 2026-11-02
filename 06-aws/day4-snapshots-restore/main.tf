# ---------- Provider configuration and remote state (S3 bucket from Day 3) ----------
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # State stored in the Day 3 bucket, under a new key for this project
  backend "s3" {
    bucket       = "bucket-id"
    key          = "day4-snapshots/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "eu-north-1"
}

# ---------- Look up the latest Amazon Linux 2023 AMI ----------
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------- Security group: SSH only from my IP ----------
resource "aws_security_group" "lab_sg" {
  name        = "terraform-snapshot-lab-sg"
  description = "Allow SSH from my IP only"

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["YOUR_IP_HERE/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terraform-snapshot-lab-sg"
  }
}

# ---------- EC2 instance (Linux, uses the ED25519 key from Day 1) ----------
resource "aws_instance" "lab_vm" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  key_name               = "key"
  vpc_security_group_ids = [aws_security_group.lab_sg.id]

  tags = {
    Name = "terraform-snapshot-lab"
  }
}

# ---------- Extra 2 GB data volume (this is what we will snapshot) ----------
# A volume can only attach to an instance in the SAME availability zone,
# so the zone is taken from the instance instead of being hardcoded.
resource "aws_ebs_volume" "data" {
  availability_zone = aws_instance.lab_vm.availability_zone
  size              = 2
  type              = "gp3"
  snapshot_id       = "snap-id"

  tags = {
    Name = "terraform-snapshot-lab-data"
  }
}

# ---------- Attach the data volume to the instance ----------
# stop_instance_before_detaching avoids a hang on destroy, because a mounted
# volume cannot be detached cleanly from a running Linux instance.
resource "aws_volume_attachment" "data_attach" {
  device_name                    = "/dev/sdf"
  volume_id                      = aws_ebs_volume.data.id
  instance_id                    = aws_instance.lab_vm.id
  stop_instance_before_detaching = true
}

# ---------- Outputs ----------
output "instance_public_ip" {
  value = aws_instance.lab_vm.public_ip
}

output "data_volume_id" {
  value = aws_ebs_volume.data.id
}

# ---------- Instance ID, needed for the AMI bonus step ----------
output "instance_id" {
  value = aws_instance.lab_vm.id
}