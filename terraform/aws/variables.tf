variable "environment" {
  description = "Environment"
  type        = string
  default     = "dev"
}


variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "test-eks-cluster"
}

variable "domain_name" {
  description = "Public Domain name registered in Route53"
  type        = string
  default     = "devawskloucks.click"
}

################################################################################
# ArgoCD Resources
################################################################################
variable "argocd_server_resources" {
  description = "Kubernetes resources for the ArgoCD server. Requests and limits for CPU and memory."
  type = object({
    requests = map(string)
    limits   = map(string)
  })

  default = {
    requests = {
      cpu    = "250m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "1Gi"
    }
  }
}

variable "argocd_controller_resources" {
  description = "Kubernetes resources for the ArgoCD controller."
  type = object({
    requests = map(string)
    limits   = map(string)
  })

  default = {
    requests = {
      cpu    = "500m"
      memory = "512Mi"
    }
    limits = {
      cpu    = "1"
      memory = "2Gi"
    }
  }
}

variable "argocd_repo_resources" {
  description = "Kubernetes resources for the ArgoCD repo server."
  type = object({
    requests = map(string)
    limits   = map(string)
  })

  default = {
    requests = {
      cpu    = "500m"
      memory = "512Mi"
    }
    limits = {
      cpu    = "1"
      memory = "2Gi"
    }
  }
}

variable "argocd_applicationset_resources" {
  description = "Kubernetes resources for the ArgoCD ApplicationSet controller."
  type = object({
    requests = map(string)
    limits   = map(string)
  })

  default = {
    requests = {
      cpu    = "200m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }
}

variable "argocd_dex_resources" {
  description = "Kubernetes resources for the ArgoCD Dex server."
  type = object({
    requests = map(string)
    limits   = map(string)
  })

  default = {
    requests = {
      cpu    = "50m"
      memory = "128Mi"
    }
    limits = {
      cpu    = "100m"
      memory = "256Mi"
    }
  }
}

variable "argocd_notifications_resources" {
  description = "Kubernetes resources for the ArgoCD notifications controller."
  type = object({
    requests = map(string)
    limits   = map(string)
  })

  default = {
    requests = {
      cpu    = "50m"
      memory = "128Mi"
    }
    limits = {
      cpu    = "100m"
      memory = "256Mi"
    }
  }
}

################################################################################
# ArgoCD External Redis
################################################################################

variable "argocd_external_redis_replication_group_id" {
  description = "Name of the ArgoCD external Redis"
  type        = string
  default     = "argocd-external-redis"
}

variable "external_redis_auth_token_update_strategy" {
  description = "Update strategy for the ArgoCD external Redis auth token"
  type        = string
  default     = "ROTATE"

  validation {
    condition     = contains(["SET", "ROTATE", "DELETE"], var.external_redis_auth_token_update_strategy)
    error_message = "Update strategy must be 'SET', 'ROTATE' or 'DELETE'."
  }
}

variable "external_redis_node_type" {
  description = "Node type for the ArgoCD external Redis"
  type        = string
  default     = "cache.t4g.small"
}

variable "external_redis_engine_version" {
  description = "Engine version for the ArgoCD external Redis"
  type        = string
  default     = "7.1"
}

variable "external_redis_multi_az_enabled" {
  description = "Multi-AZ enabled for the ArgoCD external Redis"
  type        = bool
  default     = false
}

variable "external_redis_maintenance_window" {
  description = "Maintenance window for the ArgoCD external Redis"
  type        = string
  default     = "sun:05:00-sun:09:00"
}

variable "external_redis_apply_immediately" {
  description = "Apply changes instead of waiting for the maintenance window for the ArgoCD external Redis"
  type        = bool
  default     = true
}

variable "external_redis_num_node_groups" {
  description = "Number of node groups for the ArgoCD external Redis"
  type        = number
  default     = 1
}

variable "external_redis_replicas_per_node_group" {
  description = "Number of replicas per node group for the ArgoCD external Redis"
  type        = number
  default     = 0
}

