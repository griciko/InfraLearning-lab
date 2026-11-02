# ---------- Decide if a volume is being restored or created new ----------
locals {
  restoring      = var.restored_volume_id != ""
  data_volume_id = local.restoring ? var.restored_volume_id : aws_ebs_volume.data[0].id
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
  name        = "terraform-backup-lab-sg"
  description = "Allow SSH from my IP only"

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terraform-backup-lab-sg"
  }
}

# ---------- EC2 instance, pinned to an AZ when one is given ----------
resource "aws_instance" "lab_vm" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  availability_zone      = var.availability_zone
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.lab_sg.id]

  tags = {
    Name = "terraform-backup-lab"
  }
}

# ---------- New data volume: only created when NOT restoring ----------
# The only backup-related thing is the tag. The workload never mentions vaults or plans.
resource "aws_ebs_volume" "data" {
  count             = local.restoring ? 0 : 1
  availability_zone = aws_instance.lab_vm.availability_zone
  size              = 2
  type              = "gp3"

  tags = {
    Name   = "terraform-backup-lab-data"
    backup = var.backup_tag_value
  }
}

# ---------- Attach the data volume (new or restored) to the instance ----------
resource "aws_volume_attachment" "data_attach" {
  device_name                    = "/dev/sdf"
  volume_id                      = local.data_volume_id
  instance_id                    = aws_instance.lab_vm.id
  stop_instance_before_detaching = true
}

# ---------- Write the Ansible inventory, including the data volume ID ----------
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/ansible/inventory.ini"
  content  = <<-EOT
    [lab]
    ${aws_instance.lab_vm.public_ip} ansible_user=ec2-user ansible_ssh_private_key_file=${var.ssh_key_path} ansible_ssh_common_args='-o StrictHostKeyChecking=no' data_volume_id=${local.data_volume_id}
  EOT
}
