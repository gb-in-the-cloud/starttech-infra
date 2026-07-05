terraform {
  required_version = ">=1.6.0"

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

    project_name           = var.project_name
    environment            = var.environment
    vpc_cidr               = var.vpc_cidr
    public_subnet_cidrs    = var.public_subnet_cidrs
    private_subnet_cidrs   = var.private_subnet_cidrs
    availability_zones     = var.availability_zones
}

module "eks" {
    source = "./modules/eks"

    project_name         = var.project_name
    environment          = var.environment
    vpc_id               = module.networking.vpc_id
    public_subnet_ids    = module.networking.public_subnet_ids
    private_subnet_ids   = module.networking.private_subnet_ids
    cluster_name         = var.eks.cluster_name
    cluster_version      = var.eks.cluster_version
    node_instance_type   = var.eks.node_instance_type
    node_desired_size    = var.eks.node_desired_size
    node_min_size        = var.eks.node_min_size
    node_max_size        = var.eks.node_max_size
}

module "storage" {
    source = "./modules/storage"

    project_name         = var.project_name
    environment          = var.environment
    bucket_name          = var.storage.bucket_name
    versioning_enabled   = var.storage.versioning_enabled
}

module "cdn" {
    source = "./modules/cdn"

    project_name         = var.project_name
    environment          = var.environment
    bucket_id            = module.storage.bucket_id 
    bucket_arn           = module.storage.bucket_arn
    bucket_domain        = module.storage.bucket_domain
    alb_dns_name         = module.eks.alb_dns_name
}

module "database" {
    source = "./modules/database"

    project_name               = var.project_name
    environment                = var.environment
    private_subnet_ids         = module.networking.private_subnet_ids
    vpc_id                     = module.networking.vpc_id
    eks_node_security_group_id = module.eks.node_security_group_id
    redis_node_type            = var.database.redis_node_type
}