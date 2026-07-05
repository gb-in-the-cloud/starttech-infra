variable "project_name" {
    description = "Project name used for resource naming and tagging"
    type        = string
}

variable "environment" {
    description = "Deployment environment (e.g. dev, staging, prod)"
    type        = string
}

variable "s3_bucket_name" {
    description = "Name of the S3 bucket for front end hosting"
    type        = string
}