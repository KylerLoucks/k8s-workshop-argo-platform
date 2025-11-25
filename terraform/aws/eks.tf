module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "v21.2.0"

  name               = var.eks_cluster_name
  kubernetes_version = "1.33"
  enable_irsa        = true # Allow IAM Roles for Service Accounts (IRSA)

  # Fix issue where only one principal from the "access_entries" is added to the KMS key policy; causing drift on applies with CI/CD
  kms_key_administrators = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/cloud303-support",
    aws_iam_role.eks.arn
  ]

  # Allow assumed IAM role access to the clusters resources
  access_entries = {
    cloud303-support = {
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/cloud303-support"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
    local-role-accounts = {
      principal_arn = aws_iam_role.eks.arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
    # # Allow Github Actions OIDC role to access the cluster
    # dev-github-actions = {
    #   principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/GithubOidcRole"
    #   policy_associations = {
    #     admin = {
    #       policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    #       access_scope = {
    #         type = "cluster"
    #       }
    #     }
    #   }
    # }
  }

  endpoint_public_access  = true
  endpoint_private_access = true


  #   create_kms_key = false
  #   encryption_config = {
  #     provider = {
  #       key_arn = module.kms.key_arn
  #     }
  #   }

  security_group_additional_rules = {
    vpc_ingress = {
      description = "Allow access to the EKS API from the VPC"
      type        = "ingress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }



  create_cloudwatch_log_group = false

  addons = {
    coredns = {
      most_recent = true
      configuration_values = jsonencode({
        computeType = "Fargate" # Tell CoreDNS to use Fargate for the pods. Will fail if not set since there are no node groups.
      })
    }
    kube-proxy = {
      most_recent = true
    }

    vpc-cni = {
      most_recent = true
    }
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets


  # Choose which namespaces to allow for fargate container provisioning
  fargate_profiles = {
    default = {
      name = "default"
      selectors = [
        {
          namespace = "kube-system"
        },
        {
          namespace = "default"
        },
        {
          namespace = "argocd"
        },
        {
          namespace = "external-dns"
        }
      ]
      tags = {
        Owner = var.environment
      }
    }
  }



  tags = {
    Environment = var.environment
    Owner       = var.environment
    ManagedBy   = "terraform"
  }
}


################################################################################
# EKS Role - used to access the EKS cluster API server from terraform.
# See the module.eks.access_entries for the IAM roles that are allowed to access the EKS cluster.
################################################################################
resource "aws_iam_role" "eks" {
  name = "eks-kms-admin-${data.aws_caller_identity.current.account_id}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
      },
    ]
  })
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_arn" {
  value = module.eks.cluster_arn
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}



module "external-dns" {
  source = "../modules/external-dns/"

  cluster_name              = module.eks.cluster_name
  cluster_oidc_provider_arn = module.eks.oidc_provider_arn

  # Pass the ARN of the hosted zone created by the Route53 zone module.
  external_dns_hosted_zone_arns = [
    data.aws_route53_zone.domain.arn
  ]

  external_dns_domain_filters = [var.domain_name]

  tags = {
    Environment = var.environment
    Owner       = var.environment
  }
  # Wait for the Route53 zone to be created before creating the external-dns resources.
  depends_on = [
    module.eks
  ]
}