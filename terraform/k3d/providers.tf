provider "kubernetes" {
  config_path    = local.kubeconfig_path
  config_context = local.dev_context
}

provider "kubernetes" {
  alias          = "prod"
  config_path    = local.kubeconfig_path
  config_context = local.prod_context
}

provider "helm" {
  kubernetes = {
    config_path    = local.kubeconfig_path
    config_context = local.dev_context
  }
}

provider "argocd" {
  server_addr = "localhost:8080"
  username    = "admin"
  password    = var.argocd_admin_password
  insecure    = true
}