data "aws_ami" "ubuntu_22" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# IAM rola — dozvoljavamo EC2 da čita ECR i koristi SSM
resource "aws_iam_role" "k8s_node" {
  name = "${var.project_name}-${var.environment}-k8s-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.k8s_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.k8s_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "k8s_node" {
  name = "${var.project_name}-${var.environment}-k8s-node"
  role = aws_iam_role.k8s_node.name
}

resource "aws_instance" "k8s_master" {
  ami                    = data.aws_ami.ubuntu_22.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.k8s_node.name

  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    throughput            = 125
    encrypted             = true
    delete_on_termination = true
  }

  user_data = base64encode(templatefile("${path.module}/scripts/kubeadm-init.sh.tpl", {
    kubernetes_version = var.kubernetes_version
    pod_cidr           = var.pod_cidr
    node_name          = "${var.project_name}-${var.environment}-master"
  }))

  # Disable source/dest check — potrebno za pod networking
  source_dest_check = false

  tags = {
    Name = "${var.project_name}-${var.environment}-k8s-master"
    Role = "k8s-master"
  }

  lifecycle {
    ignore_changes = [user_data, ami]
  }
}

# Dedicated EBS za Kubernetes PV (local-path-provisioner)
resource "aws_ebs_volume" "data" {
  availability_zone = "${var.aws_region}a"
  size              = var.data_volume_size_gb
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "${var.project_name}-${var.environment}-k8s-data"
  }
}

resource "aws_volume_attachment" "data" {
  device_name  = "/dev/xvdf"
  volume_id    = aws_ebs_volume.data.id
  instance_id  = aws_instance.k8s_master.id
  force_detach = true
}

# Elastic IP — stabilan public IP koji ne mjenja se pri restartu
resource "aws_eip" "master" {
  domain   = "vpc"
  instance = aws_instance.k8s_master.id

  tags = {
    Name = "${var.project_name}-${var.environment}-master-eip"
  }

  depends_on = [aws_instance.k8s_master]
}
