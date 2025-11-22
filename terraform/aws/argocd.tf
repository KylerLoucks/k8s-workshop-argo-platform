module "argocd" {
  source = "../modules/argocd"

  argocd = {
    chart_version = "9.1.1"

    values = [
      yamlencode({

        # Use externalRedis instead of the in-cluster one
        redis = {
          enabled = false
        }
        redis-ha = {
          enabled = false
        }

        externalRedis = {
          host     = module.argocd_external_redis.replication_group_primary_endpoint_address
          port     = module.argocd_external_redis.replication_group_port
          username = "default"
          # password will be injected via set_sensitive below
          # externalRedis.password
        }


        configs = {
          params = {
            "server.insecure" = true
          }
        }

        # Enable TLS when ArgoCD talks to external Redis. Will cause connection errors if not set.
        controller = {
          extraArgs = [
            "--redis-use-tls",
          ]
        }

        repoServer = {
          extraArgs = [
            "--redis-use-tls",
          ]
        }

        server = {
          extraArgs = [
            "--redis-use-tls",
          ]
          service = { type = "ClusterIP" }

          # Public ALB for webhook only
          ingress = {
            enabled          = true
            ingressClassName = "alb"
            pathType         = "Prefix"
            hosts            = ["*"] # use default hostname for alb
            # hosts            = [for domain in var.delegated_domains : "argocd.${domain}"]
            paths = ["/"]
            annotations = {
              "alb.ingress.kubernetes.io/scheme"       = "internet-facing"
              "alb.ingress.kubernetes.io/target-type"  = "ip"
              "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\":80}]"
              #   "alb.ingress.kubernetes.io/certificate-arn" = [for domain in var.delegated_domains : aws_acm_certificate.argocd[domain].arn]
            }
          }

          # Internal ALB for UI
          #   additionalIngress = [{
          #     name             = "ui-internal"
          #     ingressClassName = "alb"
          #     # hosts            = ["argocd.${local.private_domain}"]
          #     paths            = ["/"]
          #     annotations = {
          #       "alb.ingress.kubernetes.io/scheme"       = "internal"
          #       "alb.ingress.kubernetes.io/target-type"  = "ip"
          #       "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\":80}]"
          #     }
          #   }]
        }
      })
    ]

    set_sensitive = [
      # Argo CD admin password (bcrypt)
      {
        name  = "configs.secret.argocdServerAdminPassword"
        value = bcrypt_hash.argo.id
      },


      # External Redis password from Secrets Manager. Must be plaintext since it's passed to the external Redis.
      {
        name  = "externalRedis.password"
        value = jsondecode(aws_secretsmanager_secret_version.argocd_redis_auth.secret_string)["redis-password"]
      }
    ]
  }

  depends_on = [
    module.eks,
    helm_release.alb_controller,
  ]
}




################################################################################
# ArgoCD External Redis
################################################################################
locals {
  argocd_redis_auth_token = jsondecode(aws_secretsmanager_secret_version.argocd_redis_auth.secret_string)["redis-password"]
}

module "argocd_external_redis" {
  source  = "terraform-aws-modules/elasticache/aws"
  version = "1.10.3"

  replication_group_id = var.argocd_external_redis_replication_group_id

  engine_version = var.external_redis_engine_version
  node_type      = var.external_redis_node_type

  # Auth token (requires transit encryption to be enabled)
  transit_encryption_enabled = true
  auth_token                 = local.argocd_redis_auth_token
  # Don't destroy the Redis cluster when the auth token is updated
  auth_token_update_strategy = var.external_redis_auth_token_update_strategy

  multi_az_enabled   = var.external_redis_multi_az_enabled
  maintenance_window = var.external_redis_maintenance_window

  # Don't wait for the maintenance window to apply the changes
  apply_immediately = var.external_redis_apply_immediately



  # Single node group and no replicas
  num_node_groups         = var.external_redis_num_node_groups
  replicas_per_node_group = var.external_redis_replicas_per_node_group

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