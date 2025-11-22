variable "argocd_admin_password" {
  description = "Password for the ArgoCD admin user"
  type        = string
  default     = "admin"
}

variable "github_webhook_secret" {
  description = "Secret for the GitHub webhook. This is used for instant syncs from GitHub instead of the limted sync interval."
  type        = string
  default     = "secret-value-here"
}

variable "prod_cluster_server" {
  description = "API server URL for the prod cluster (as seen by Argo CD)"
  type        = string
  default     = "https://host.k3d.internal:6551"
}
