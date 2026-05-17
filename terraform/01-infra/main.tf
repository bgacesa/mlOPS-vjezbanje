module "network" {
  source = "./modules/network"

  project_name       = var.project_name
  environment        = var.environment
  aws_region         = var.aws_region
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
  allowed_cidr_blocks = var.allowed_cidr_blocks
}

module "compute" {
  source = "./modules/compute"

  project_name       = var.project_name
  environment        = var.environment
  aws_region         = var.aws_region
  subnet_id          = module.network.public_subnet_id
  security_group_id  = module.network.k8s_sg_id
  instance_type      = var.instance_type
  key_name           = var.key_name
  root_volume_size_gb = var.root_volume_size_gb
  data_volume_size_gb = var.data_volume_size_gb
  kubernetes_version = var.kubernetes_version
  pod_cidr           = var.pod_cidr
}
