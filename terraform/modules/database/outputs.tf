output "redis_endpoint" {
  description = "Redis cluster endpoint address"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "redis_port" {
  description = "Redis cluster port"
  value       = aws_elasticache_cluster.redis.port
}

output "redis_connection_string" {
  description = "Full Redis connection string"
  value       = "redis://${aws_elasticache_cluster.redis.cache_nodes[0].address}:${aws_elasticache_cluster.redis.port}"
}

output "redis_security_group_id" {
  description = "Security group ID of the Redis cluster"
  value       = aws_security_group.redis.id
}

output "redis_subnet_group_name" {
  description = "Name of the ElastiCache subnet group"
  value       = aws_elasticache_subnet_group.redis.name
}

output "redis_cluster_id" {
  description = "ElastiCache cluster ID"
  value       = aws_elasticache_cluster.redis.cluster_id
}