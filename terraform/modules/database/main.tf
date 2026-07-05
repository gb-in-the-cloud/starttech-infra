# ─── Redis Security Group ─────────────────────────────────────────────────────
resource "aws_security_group" "redis" {
  name        = "${var.project_name}-redis-sg"
  description = "Security group for ElastiCache Redis"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = var.redis_port
    to_port         = var.redis_port
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group]
    description     = "Allow Redis traffic from EKS worker nodes only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-redis-sg"
    Environment = var.environment
  }
}

# ─── ElastiCache Subnet Group ─────────────────────────────────────────────────
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.project_name}-redis-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name        = "${var.project_name}-redis-subnet-group"
    Environment = var.environment
  }
}

# ─── ElastiCache Parameter Group ─────────────────────────────────────────────
resource "aws_elasticache_parameter_group" "redis" {
  name   = "${var.project_name}-redis-params"
  family = "redis7"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  tags = {
    Name        = "${var.project_name}-redis-params"
    Environment = var.environment
  }
}

# ─── ElastiCache Redis Cluster ────────────────────────────────────────────────
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "starttech-redis"
  engine               = "redis"
  engine_version       = var.redis_engine_version
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = aws_elasticache_parameter_group.redis.name
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.redis.id]
  port                 = var.redis_port

  # Maintenance and backup
  maintenance_window       = "sun:05:00-sun:06:00"
  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = "03:00-04:00"

  # Notifications
  apply_immediately = true

  tags = {
    Name        = "starttech-redis"
    Environment = var.environment
  }
}