# ---------- Values needed for SSH and the checks ----------
output "instance_public_ip" {
  value = aws_instance.lab_vm.public_ip
}

output "volume_id" {
  value = local.data_volume_id
}

output "volume_arn" {
  value = one(aws_ebs_volume.data[*].arn)
}