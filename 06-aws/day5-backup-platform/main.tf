# ---------- Vault: where the recovery points are stored ----------
# force_destroy is NOT set on purpose: a vault holding recovery points cannot be deleted by accident
resource "aws_backup_vault" "main" {
  name = var.vault_name
}

# ---------- Trust policy: allows the AWS Backup service to assume this role ----------
data "aws_iam_policy_document" "backup_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

# ---------- Role that AWS Backup uses to take and restore backups ----------
resource "aws_iam_role" "backup" {
  name               = "lab-aws-backup-role"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json
}

# ---------- Permissions: AWS-managed policy for taking backups ----------
resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# ---------- Permissions: AWS-managed policy for restores (used in step 6) ----------
resource "aws_iam_role_policy_attachment" "restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# ---------- Plan: daily schedule and how long each backup is kept ----------
resource "aws_backup_plan" "daily" {
  name = "lab-daily-plan"

  rule {
    rule_name         = "daily-0300-utc"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 3 * * ? *)"

    lifecycle {
      delete_after = var.retention_days
    }
  }
}

# ---------- Selection: which resources the plan covers, chosen by TAG ----------
# depends_on gives IAM time to finish creating the role permissions first
resource "aws_backup_selection" "tagged" {
  name         = "tagged-backup-daily"
  plan_id      = aws_backup_plan.daily.id
  iam_role_arn = aws_iam_role.backup.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "backup"
    value = var.backup_tag_value
  }

  depends_on = [
    aws_iam_role_policy_attachment.backup,
    aws_iam_role_policy_attachment.restore,
  ]
}