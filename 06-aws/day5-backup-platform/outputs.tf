# ---------- Values needed by the CLI steps later ----------
output "vault_name" {
  value = aws_backup_vault.main.name
}

output "backup_role_arn" {
  value = aws_iam_role.backup.arn
}

output "backup_plan_id" {
  value = aws_backup_plan.daily.id
}