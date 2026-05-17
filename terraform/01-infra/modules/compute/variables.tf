variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "key_name" {
  type = string
}

variable "root_volume_size_gb" {
  type    = number
  default = 50
}

variable "data_volume_size_gb" {
  type    = number
  default = 100
}

variable "kubernetes_version" {
  type    = string
  default = "1.29"
}

variable "pod_cidr" {
  type    = string
  default = "10.244.0.0/16"
}
