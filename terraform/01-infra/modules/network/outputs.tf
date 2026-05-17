output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "k8s_sg_id" {
  value = aws_security_group.k8s.id
}
