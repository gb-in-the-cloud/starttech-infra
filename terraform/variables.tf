variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "The name of the project."
  type        = string
  default     = "starttech-infra"
}

variable "environment" {
  description = "The environment for the deployment (e.g., dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b"]
}

#----EKS----#
variable "eks_cluster_version" {
  description = "The version of the EKS cluster."
  type        = string
  default     = "1.34"
}

variable "eks_node_instance_type" {
  description = "The instance type for the EKS worker nodes."
  type        = string
  default     = "t3.medium"
}

variable "eks_node_desired_size" {
  description = "The desired number of worker nodes in the EKS node group."
  type        = number
  default     = 2
}

variable "eks_node_max_size" {
  description = "The maximum number of worker nodes in the EKS node group."
  type        = number
  default     = 4
}

variable "eks_node_min_size" {
  description = "The minimum number of worker nodes in the EKS node group."
  type        = number
  default     = 2
}

#----Storage----#
variable "s3_bucket_name" {
  description = "The name of the S3 bucket."
  type        = string
  default     = "starttech-infra-bucket"
}

#----Database----#
variable "redis_node_type" {
  description = "The instance class for the Redis instance."
  type        = string
  default     = "cache.t3.micro"
}