# ---------- Provider configuration ----------
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-north-1"
}

# ---------- Look up the latest Amazon Linux AMI ----------
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
  name        = "terraform-ansible-lab-sg"
  description = "Allow SSH from my IP only"

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["YOUR_IP_HERE/32"]
  }
# New block — allows HTTP so we can actually test nginx from a browser
  ingress {
    description = "HTTP from my IP"
    from_port   = 80
    to_port     = 80
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
    Name = "terraform-ansible-lab-sg"
  }
}

# ---------- EC2 instance ----------
resource "aws_instance" "lab_vm" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  key_name               = "key"
  vpc_security_group_ids = [aws_security_group.lab_sg.id]

  tags = {
    Name = "terraform-ansible-lab"
  }
}

# ---------- Output the public IP, for use in the next step ----------
output "instance_public_ip" {
  value = aws_instance.lab_vm.public_ip
}

# ---------- Write the instance IP into an Ansible inventory file ----------
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/inventory.ini"
  content  = <<-EOT
    [lab]
    ${aws_instance.lab_vm.public_ip} ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/key.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no'
  EOT
}

# ---------- SNS topic for EC2 state-change alerts ----------
resource "aws_sns_topic" "ec2_alerts" {
  name = "ec2-training-alerts"
}

# ---------- Email subscription (requires manual confirmation) ----------
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.ec2_alerts.arn
  protocol  = "email"
  endpoint  = "your-email@example.com"
}

# ---------- Allow EventBridge to publish to this SNS topic ----------
resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn = aws_sns_topic.ec2_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridgePublish"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.ec2_alerts.arn
      }
    ]
  })
}

# ---------- EventBridge rule: watch for EC2 state changes ----------
resource "aws_cloudwatch_event_rule" "ec2_state_change" {
  name        = "ec2-state-change"
  description = "Notify on EC2 instance start, stop, terminate"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
    detail = {
      state = ["running", "stopped", "terminated"]
    }
  })
}

# ---------- Connect the EventBridge rule to the SNS topic ----------
resource "aws_cloudwatch_event_target" "sns" {
  rule      = aws_cloudwatch_event_rule.ec2_state_change.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.ec2_alerts.arn
}