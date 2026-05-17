output "instance_public_ip" {
  value = aws_eip.master.public_ip
}

output "instance_private_ip" {
  value = aws_instance.k8s_master.private_ip
}

output "instance_id" {
  value = aws_instance.k8s_master.id
}

output "iam_role_arn" {
  value = aws_iam_role.k8s_node.arn
}
