output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Public Subnet IDs"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private Subnet IDs"
  value       = module.networking.private_subnet_ids
}

output "eks_cluster_name" {
  description = "EKS Cluster Name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS Cluster Endpoint"
  value       = module.eks.cluster_endpoint
}

output "s3_bucket_name" {
  description = "S3 Bucket Name"
  value       = module.storage.bucket_id
}

output "cloudfront_domain" {
  description = "CloudFront Distribution Domain Name"
  value       = module.cdn.cloudfront_domain
}

output "redis_endpoint" {
  description = "Redis Endpoint"
  value       = module.database.redis_endpoint
}