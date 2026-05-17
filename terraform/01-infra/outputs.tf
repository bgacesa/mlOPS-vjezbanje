output "instance_public_ip" {
  description = "Elastic IP adresa Kubernetes master nodea"
  value       = module.compute.instance_public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = module.compute.instance_id
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "subnet_id" {
  description = "Public subnet ID"
  value       = module.network.public_subnet_id
}

output "kubeconfig_fetch_command" {
  description = "Komanda za preuzimanje kubeconfig sa master nodea"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${module.compute.instance_public_ip} 'sudo cat /etc/kubernetes/admin.conf'"
}

output "bootstrap_log_command" {
  description = "Komanda za praćenje bootstrap loga na instanci"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${module.compute.instance_public_ip} 'tail -f /var/log/kubeadm-init.log'"
}

output "ssh_command" {
  description = "SSH komanda za spajanje na master node"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${module.compute.instance_public_ip}"
}
