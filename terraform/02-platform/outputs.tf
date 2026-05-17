output "ecr_repository_url" {
  description = "ECR repository URL za push Docker image-a"
  value       = aws_ecr_repository.mlops.repository_url
}

output "minio_nodeport_url" {
  description = "MinIO S3 API URL (NodePort)"
  value       = "http://<NODE_IP>:30900"
}

output "minio_console_url" {
  description = "MinIO Web Console URL (NodePort)"
  value       = "http://<NODE_IP>:30901"
}

output "mlflow_url" {
  description = "MLflow tracking server URL"
  value       = "http://<NODE_IP>:30500"
}

output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = "http://<NODE_IP>:30300"
}

output "argocd_url" {
  description = "ArgoCD UI URL"
  value       = "http://<NODE_IP>:30080"
}

output "argo_workflows_url" {
  description = "Argo Workflows UI URL"
  value       = "http://<NODE_IP>:30274"
}

output "argocd_admin_password_command" {
  description = "Komanda za dobivanje ArgoCD admin lozinke"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
