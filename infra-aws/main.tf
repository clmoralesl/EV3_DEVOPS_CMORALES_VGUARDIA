terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

variable "eks_cluster_role_arn" {
  type        = string
  description = "ARN del rol de EKS Cluster (si se requiere usar uno especifico de AWS Academy)"
  default     = ""
}

variable "eks_node_role_arn" {
  type        = string
  description = "ARN del rol de EKS Nodes (si se requiere usar uno especifico de AWS Academy)"
  default     = ""
}

# ==========================================
# 1. REDES (VPC, Subnets, Gateways, Tablas)
# ==========================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "VPC-Proyecto-EKS"
    "kubernetes.io/cluster/cluster-proyecto-ep3" = "shared"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "IGW-Proyecto" }
}

# Subnets Públicas (Con tags requeridos por Kubernetes para ALBs/CLBs públicos)
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name                                         = "Subnet-Public-A"
    "kubernetes.io/role/elb"                     = "1"
    "kubernetes.io/cluster/cluster-proyecto-ep3" = "shared"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name                                         = "Subnet-Public-B"
    "kubernetes.io/role/elb"                     = "1"
    "kubernetes.io/cluster/cluster-proyecto-ep3" = "shared"
  }
}

# Subnets Privadas para Aplicación (Con tags requeridos por Kubernetes para LBs internos)
resource "aws_subnet" "private_app_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name                                         = "Subnet-Private-App-A"
    "kubernetes.io/role/internal-elb"            = "1"
    "kubernetes.io/cluster/cluster-proyecto-ep3" = "shared"
  }
}

resource "aws_subnet" "private_app_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.5.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name                                         = "Subnet-Private-App-B"
    "kubernetes.io/role/internal-elb"            = "1"
    "kubernetes.io/cluster/cluster-proyecto-ep3" = "shared"
  }
}

# Subnets Privadas para Base de Datos
resource "aws_subnet" "private_db_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name                                         = "Subnet-Private-DB-A"
    "kubernetes.io/cluster/cluster-proyecto-ep3" = "shared"
  }
}

resource "aws_subnet" "private_db_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.6.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name                                         = "Subnet-Private-DB-B"
    "kubernetes.io/cluster/cluster-proyecto-ep3" = "shared"
  }
}

# NAT Gateway para subredes privadas
resource "aws_eip" "nat_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.gw]
  tags       = { Name = "NAT-EIP" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_a.id
  tags          = { Name = "Main-NAT-Gateway" }
}

# Tablas de Ruteo
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "RT-Publica" }
}

resource "aws_route_table_association" "public_assoc_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_assoc_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "RT-Privada" }
}

resource "aws_route_table_association" "app_assoc_a" {
  subnet_id      = aws_subnet.private_app_a.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "app_assoc_b" {
  subnet_id      = aws_subnet.private_app_b.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "db_assoc_a" {
  subnet_id      = aws_subnet.private_db_a.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "db_assoc_b" {
  subnet_id      = aws_subnet.private_db_b.id
  route_table_id = aws_route_table.private_rt.id
}

# ==========================================
# 2. REGISTRO DE CONTENEDORES (ECR)
# ==========================================

resource "aws_ecr_repository" "repo_db_ventas" {
  name                 = "ep3-db-ventas"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_repository" "repo_db_despachos" {
  name                 = "ep3-db-despachos"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_repository" "repo_front" {
  name                 = "ep3-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_repository" "repo_back_ventas" {
  name                 = "ep3-back-ventas"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_repository" "repo_back_despachos" {
  name                 = "ep3-back-despachos"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
}

# ==========================================
# 3. CLÚSTER EKS (ELASTIC KUBERNETES SERVICE)
# ==========================================

resource "aws_eks_cluster" "main" {
  name     = "cluster-proyecto-ep3"
  role_arn = var.eks_cluster_role_arn != "" ? var.eks_cluster_role_arn : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"

  vpc_config {
    subnet_ids = [
      aws_subnet.public_a.id,
      aws_subnet.public_b.id,
      aws_subnet.private_app_a.id,
      aws_subnet.private_app_b.id
    ]
    # No especificamos security_group_ids para que AWS EKS cree y gestione
    # automáticamente el grupo de seguridad por defecto del clúster (práctica recomendada).
  }

  # Habilitar logs del plano de control en CloudWatch
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

# ==========================================
# 4. GRUPO DE NODOS PARA APLICACIONES (FRONTEND & BACKEND)
# ==========================================

resource "aws_eks_node_group" "nodos_app" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "nodos-app"
  node_role_arn   = var.eks_node_role_arn != "" ? var.eks_node_role_arn : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
  subnet_ids      = [aws_subnet.private_app_a.id, aws_subnet.private_app_b.id]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.medium"]
  ami_type       = "AL2_x86_64"

  labels = {
    role = "app"
  }

  depends_on = [
    aws_eks_cluster.main
  ]
}

# ==========================================
# 5. GRUPO DE NODOS PARA BASES DE DATOS (MYSQL)
# ==========================================

resource "aws_eks_node_group" "nodos_db" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "nodos-db"
  node_role_arn   = var.eks_node_role_arn != "" ? var.eks_node_role_arn : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
  subnet_ids      = [aws_subnet.private_app_a.id, aws_subnet.private_app_b.id]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  instance_types = ["t3.medium"]
  ami_type       = "AL2_x86_64"

  labels = {
    role = "db"
  }

  depends_on = [
    aws_eks_cluster.main
  ]
}

# ==========================================
# SALIDAS (OUTPUTS)
# ==========================================

output "cluster_name" {
  value       = aws_eks_cluster.main.name
  description = "Nombre del cluster EKS"
}

output "cluster_endpoint" {
  value       = aws_eks_cluster.main.endpoint
  description = "Endpoint del API Server del cluster EKS"
}

output "update_kubeconfig_command" {
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region us-east-1"
  description = "Comando para configurar kubectl de forma local"
}
