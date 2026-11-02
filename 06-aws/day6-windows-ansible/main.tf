# ---------- Look up the latest Windows Server 2022 AMI (Amazon-provided) ----------
data "aws_ami" "windows" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------- Security group: WinRM HTTPS, RDP and HTTP, all from my IP only ----------
resource "aws_security_group" "win_sg" {
  name        = "terraform-day6-windows-sg"
  description = "WinRM HTTPS, RDP and HTTP from my IP only"

  ingress {
    description = "WinRM over HTTPS from my IP"
    from_port   = 5986
    to_port     = 5986
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  ingress {
    description = "RDP from my IP (for checking things by eye)"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  ingress {
    description = "HTTP from my IP (IIS test page)"
    from_port   = 80
    to_port     = 80
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
    Name = "terraform-day6-windows-sg"
  }
}

# ---------- Windows instance. The user data enables WinRM over HTTPS at first boot ----------
# user_data_replace_on_change: the script only runs at first boot, so a changed script needs a new instance
resource "aws_instance" "win_vm" {
  ami                         = data.aws_ami.windows.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.win_sg.id]
  user_data                   = "<powershell>\n${file("${path.module}/winrm-setup.ps1")}\n</powershell>"
  user_data_replace_on_change = true

  # Explicit root disk, deleted automatically on terminate
  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "terraform-day6-windows"
  }
}

# ---------- Extra 2 GB data disk: Ansible will initialize and format it ----------
resource "aws_ebs_volume" "data" {
  availability_zone = aws_instance.win_vm.availability_zone
  size              = 2
  type              = "gp3"

  tags = {
    Name = "terraform-day6-windows-data"
  }
}

# ---------- Attach the data disk to the instance ----------
# If AWS rejects the device name for Windows, try /dev/sdf and tell me
resource "aws_volume_attachment" "data_attach" {
  device_name                    = "xvdf"
  volume_id                      = aws_ebs_volume.data.id
  instance_id                    = aws_instance.win_vm.id
  stop_instance_before_detaching = true
}

# ---------- Write the Ansible inventory: only the host. Connection settings live in group_vars ----------
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/ansible/inventory.ini"
  content  = <<-EOT
    [win]
    ${aws_instance.win_vm.public_ip}
  EOT
}