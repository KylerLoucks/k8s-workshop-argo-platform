terraform {

  #   backend "s3" {}

  required_version = "~> 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.14"
    }
    sops = {
      source  = "carlpett/sops",
      version = "1.2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    bcrypt = {
      source  = "viktorradnai/bcrypt"
      version = "~> 0.1"
    }
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "~> 7.11"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  ignore_tags {
    key_prefixes = ["map-migrated"]
  }
}


# Kubernetes Provider
# Must pass in the cluster name as a variable instead of using module output reference to avoid race conditions
# https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2501#issuecomment-1468836777
# https://github.com/hashicorp/terraform-provider-kubernetes/blob/main/_examples/eks/kubernetes-config/main.tf

provider "aws" {
  alias  = "eks_access"
  region = "us-east-1"

  dynamic "assume_role" {
    for_each = aws_iam_role.eks.arn != null && aws_iam_role.eks.arn != "" ? [1] : []
    content {
      role_arn     = aws_iam_role.eks.arn
      session_name = "terraform-eks-cluster-access"
    }
  }
}


data "aws_eks_cluster_auth" "cluster" {
  provider = aws.eks_access

  name = module.eks.cluster_name
}

################################################################################
# Kubernetes Provider
################################################################################
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# Helm
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

provider "argocd" {
  # Argo CD is exposed via an internet-facing ALB listening on HTTP :80.
  # The provider defaults to HTTPS on :443, which causes timeouts against this ALB.
  # Use plain HTTP on port 80 instead.
  server_addr = "argocd.${var.domain_name}:443"
  username    = "admin"
  password    = random_password.argocd.result
}