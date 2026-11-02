# ---------- Values needed for the checks ----------
output "instance_id" {
  value = aws_instance.win_vm.id
}

output "instance_public_ip" {
  value = aws_instance.win_vm.public_ip
}

output "data_volume_id" {
  value = aws_ebs_volume.data.id
}