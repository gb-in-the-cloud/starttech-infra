variable "project_name" {
  description = "Project name used for naming and tagging"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ElastiCache will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ElastiCache subnet group"
  type        = list(string)
}

variable "eks_node_security_group" {
  description = "Security group ID of EKS worker nodes"
  type        = string
}

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_port" {
  description = "Port Redis listens on"
  type        = number
  default     = 6379
}

variable "redis_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.1"
}

variable "snapshot_retention_limit" {
  description = "Number of days to retain automatic snapshots"
  type        = number
  default     = 1
}