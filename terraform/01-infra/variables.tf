variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Project name (used for resource naming and tagging)"
  type        = string
  default     = "mlops-vjezba"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR block"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type (min t3.xlarge za single-node Kubernetes + ML stack)"
  type        = string
  default     = "t3.2xlarge"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 50
}

variable "data_volume_size_gb" {
  description = "Data EBS volume size in GB (za PV storage)"
  type        = number
  default     = 100
}

variable "key_name" {
  description = "Naziv EC2 SSH key para (mora postojati u AWS regionu)"
  type        = string
}

variable "allowed_cidr_blocks" {
  description = "CIDR blokovi kojima je dozvoljen pristup SSH i Kubernetes API-ju"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "kubernetes_version" {
  description = "Kubernetes verzija za kubeadm install (major.minor, npr. '1.29')"
  type        = string
  default     = "1.29"
}

variable "pod_cidr" {
  description = "Pod network CIDR za Flannel CNI"
  type        = string
  default     = "10.244.0.0/16"
}
