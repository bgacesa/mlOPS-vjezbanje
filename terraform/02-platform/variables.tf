variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "mlops-vjezba"
}

variable "environment" {
  description = "Environment"
  type        = string
  default     = "dev"
}

variable "kubeconfig_path" {
  description = "Putanja do kubeconfig fajla (generisan u fazi 01-infra)"
  type        = string
  default     = "~/.kube/mlops-config"
}

variable "minio_root_user" {
  description = "MinIO root korisničko ime"
  type        = string
  default     = "minio-admin"
}

variable "minio_root_password" {
  description = "MinIO root lozinka (min 8 karaktera)"
  type        = string
  sensitive   = true
}

variable "mlflow_tracking_username" {
  description = "MLflow basic auth korisničko ime (opcionalno)"
  type        = string
  default     = "mlflow"
}

variable "kubeflow_version" {
  description = "Kubeflow manifests tag (GitHub ref)"
  type        = string
  default     = "v1.8.1"
}

variable "argocd_version" {
  description = "ArgoCD Helm chart verzija"
  type        = string
  default     = "6.7.14"
}

variable "grafana_admin_password" {
  description = "Grafana admin lozinka"
  type        = string
  default     = "mlops-grafana-admin"
  sensitive   = true
}
