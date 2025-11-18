variable "argocd_admin_password" {
  description = "Password for the ArgoCD admin user"
  type        = string
  default     = "admin"
}

variable "prod_cluster_server" {
  description = "API server URL for the prod cluster (as seen by Argo CD)"
  type        = string
  default     = "https://host.k3d.internal:6551"
}
