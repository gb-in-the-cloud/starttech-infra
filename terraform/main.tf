terraform {
  required_version = ">=1.6.0"

  backend "s3" {
    bucket = "starttech-tfstate-gb-2026"
    key    = "starttech/terraform.tfstate"
    region = "eu-west-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

module "networking" {
  source = "./modules/networking"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

module "eks" {
  source = "./modules/eks"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  cluster_version    = var.eks_cluster_version
  node_instance_type = var.eks_node_instance_type
  node_desired_size  = var.eks_node_desired_size
  node_min_size      = var.eks_node_min_size
  node_max_size      = var.eks_node_max_size
}

module "storage" {
  source = "./modules/storage"

  project_name   = var.project_name
  environment    = var.environment
  s3_bucket_name = var.s3_bucket_name
}

module "cdn" {
  source = "./modules/cdn"

  project_name     = var.project_name
  environment      = var.environment
  s3_bucket_id     = module.storage.s3_bucket_id
  s3_bucket_arn    = module.storage.s3_bucket_arn
  s3_bucket_domain = module.storage.s3_bucket_domain
  alb_dns_name     = module.eks.alb_dns_name
}

module "database" {
  source = "./modules/database"

  project_name            = var.project_name
  environment             = var.environment
  private_subnet_ids      = module.networking.private_subnet_ids
  vpc_id                  = module.networking.vpc_id
  eks_node_security_group = module.eks.node_security_group_id
  redis_node_type         = var.redis_node_type
}