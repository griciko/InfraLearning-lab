# ---------- Provider configuration ----------
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Store state in S3 instead of on this laptop
  backend "s3" {
    bucket       = "your-bucket-name"  # Replace with your S3 bucket name
    key          = "your-bucket-key"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "eu-north-1"
}

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

# ---------- Security group: RDP (3389) only from my IP ----------
resource "aws_security_group" "win_sg" {
  name        = "terraform-windows-lab-sg"
  description = "Allow RDP from my IP only"

  ingress {
    description = "RDP from my IP"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["YOUR-IP-ADDRESS/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terraform-windows-lab-sg"
  }
}

# ---------- Windows EC2 instance ----------
resource "aws_instance" "win_vm" {
  ami                    = data.aws_ami.windows.id
  instance_type          = "c7i-flex.large"
  key_name               = "YOUR-KEY-NAME"  # Replace with your key pair name
  vpc_security_group_ids = [aws_security_group.win_sg.id]

  # Root disk: explicit size, and deleted automatically on terminate (no orphaned volume)
  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "terraform-windows-lab"
  }
}

# ---------- Outputs: what we need to connect ----------
output "instance_public_ip" {
  value = aws_instance.win_vm.public_ip
}

output "instance_id" {
  value = aws_instance.win_vm.id
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