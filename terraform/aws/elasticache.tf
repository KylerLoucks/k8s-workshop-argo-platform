locals {
  argocd_redis_auth_token = jsondecode(aws_secretsmanager_secret_version.argocd_redis_auth.secret_string)["redis-password"]
}


################################################################################
# ArgoCD External Redis
################################################################################
module "argocd_external_redis" {
  source  = "terraform-aws-modules/elasticache/aws"
  version = "1.10.3"

  replication_group_id = "argocd-external-redis-replication-group"

  engine_version = "7.1"
  node_type      = "cache.t4g.small"

  # Auth token (requires transit encryption to be enabled)
  transit_encryption_enabled = true
  auth_token                 = local.argocd_redis_auth_token

  multi_az_enabled   = false
  maintenance_window = "sun:05:00-sun:09:00"

  # Apply immediately to avoid drift
  apply_immediately = true



  # Single node group and no replicas
  num_node_groups         = 1
  replicas_per_node_group = 0

  # Security group
  vpc_id                = module.vpc.vpc_id
  create_security_group = false
  security_group_ids = [
    aws_security_group.argocd_external_redis.id
  ]

  # Subnet Group
  subnet_ids = module.vpc.database_subnets

  # Parameter Group
  create_parameter_group = true
  parameter_group_family = "redis7"
  parameters = [
    {
      name  = "latency-tracking"
      value = "yes"
    }
  ]

  tags = {
    Terraform   = "true"
    Environment = var.environment
  }
}


# Security Group for ElastiCache Redis replication groups
resource "aws_security_group" "argocd_external_redis" {
  name_prefix = "argocd-external-redis-"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for ArgoCD External Redis replication groups"

  ingress {
    description = "Redis traffic from EKS (Fargate + nodes)"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    security_groups = [
      module.eks.cluster_primary_security_group_id,
      module.eks.node_security_group_id
    ]
  }

  # Allow Redis access from EKS cluster
  egress {
    description = "Outbound to VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  tags = {
    Name        = "argocd-external-redis-sg"
    Environment = var.environment
    Purpose     = "ArgoCD External Redis access"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Output the ElastiCache security group ID for use in ElastiCache charts
output "argocd_external_redis_security_group_id" {
  description = "ID of the security group for ArgoCD External Redis replication groups"
  value       = aws_security_group.argocd_external_redis.id
}


output "external_redis_endpoint" {
  value = module.argocd_external_redis.replication_group_primary_endpoint_address
}

output "external_redis_port" {
  value = module.argocd_external_redis.replication_group_port
}