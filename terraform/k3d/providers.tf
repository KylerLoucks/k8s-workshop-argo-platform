provider "kubernetes" {
  config_path    = local.kubeconfig_path
  config_context = local.management_context
}

provider "kubernetes" {
  alias          = "prod"
  config_path    = local.kubeconfig_path
  config_context = local.prod_context
}

provider "helm" {
  kubernetes = {
    config_path    = local.kubeconfig_path
    config_context = local.management_context
  }
}

# This provider uses port-forwarding to the Argo CD server.
provider "argocd" {
  port_forward_with_namespace = "argocd" # if server is in namespace argocd

  # How Terraform authenticates to Argo CD itself:
  username = "admin"
  password = var.argocd_admin_password
  kubernetes {
    config_context = local.management_context
  }
}

# provider "argocd" {
#   server_addr = "localhost:8080"
#   username    = "admin"
#   password    = var.argocd_admin_password
#   insecure    = true
# }