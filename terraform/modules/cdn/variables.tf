variable "project_name" {
  description = "Project name used for naming and tagging"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "s3_bucket_id" {
  description = "ID of the S3 bucket for frontend hosting"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket for frontend hosting"
  type        = string
}

variable "s3_bucket_domain" {
  description = "Regional domain name of the S3 bucket"
  type        = string
}

variable "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  type        = string
  default     = "placeholder.example.com"
}