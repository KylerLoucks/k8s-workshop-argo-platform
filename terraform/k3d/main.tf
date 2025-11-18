########################################
# k3d prod cluster CA + kubeconfig info
########################################

locals {
  kubeconfig_path = pathexpand("~/.kube/config")
  dev_context     = "k3d-dev"
  prod_context    = "k3d-prod"

  kubeconfig_doc = yamldecode(file(local.kubeconfig_path))

  prod_cluster_doc = try(
    one([for c in local.kubeconfig_doc.clusters : c if c.name == local.prod_context]),
    null
  )

  # from kubeconfig: clusters[].cluster.certificate-authority-data (base64)
  prod_cluster_ca_data = try(local.prod_cluster_doc.cluster["certificate-authority-data"], null)

  # PEM string (this is what argocd_cluster.config.tls_client_config.ca_data wants)
  prod_cluster_ca = local.prod_cluster_ca_data != null ? base64decode(local.prod_cluster_ca_data) : null

  # API server URL for k3d prod (you already have this as a var)
  prod_cluster_server = var.prod_cluster_server

  # example helm overrides for Argo CD itself
  argocd_values = [
    yamlencode({
      server = {
        service = {
          type = "ClusterIP"
        }
      }
    })
  ]
}

########################################
# SA + RBAC in k3d prod cluster
########################################

resource "kubernetes_service_account_v1" "argocd_manager" {
  provider = kubernetes.prod

  metadata {
    name      = "argocd-manager"
    namespace = "kube-system"
  }

  automount_service_account_token = true
}

resource "kubernetes_cluster_role_v1" "argocd_manager" {
  provider = kubernetes.prod

  metadata {
    name = "argocd-manager-role"
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }

  rule {
    non_resource_urls = ["*"]
    verbs             = ["*"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "argocd_manager_binding" {
  provider = kubernetes.prod

  metadata {
    name = "argocd-manager-role-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.argocd_manager.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.argocd_manager.metadata[0].name
    namespace = kubernetes_service_account_v1.argocd_manager.metadata[0].namespace
  }
}

########################################
# ServiceAccount token secret (waits for token)
########################################

resource "kubernetes_secret_v1" "argocd_manager_token" {
  provider = kubernetes.prod

  metadata {
    name      = "argocd-cluster-token"
    namespace = kubernetes_service_account_v1.argocd_manager.metadata[0].namespace
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.argocd_manager.metadata[0].name
    }
  }

  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true

  depends_on = [
    kubernetes_service_account_v1.argocd_manager,
    kubernetes_cluster_role_binding_v1.argocd_manager_binding,
  ]
}

########################################
# Read the SA token via data source
########################################

data "kubernetes_secret_v1" "argocd_manager_token" {
  provider = kubernetes.prod

  metadata {
    name      = kubernetes_secret_v1.argocd_manager_token.metadata[0].name
    namespace = kubernetes_secret_v1.argocd_manager_token.metadata[0].namespace
  }

  depends_on = [
    kubernetes_secret_v1.argocd_manager_token,
  ]
}

locals {
  # token is already a JWT string, just strip sensitivity wrapper
  prod_cluster_token = nonsensitive(
    data.kubernetes_secret_v1.argocd_manager_token.data["token"]
  )
}

########################################
# Argo CD module
########################################

resource "bcrypt_hash" "argocd_admin" {
  cleartext = var.argocd_admin_password
}

module "argocd" {
  source = "../modules/argocd"

  argocd = {
    name             = "argo-cd"
    namespace        = "argocd"
    create_namespace = true
    chart_version    = "9.1.1"
    repository       = "https://argoproj.github.io/argo-helm"
    values           = local.argocd_values

    set_sensitive = [
      {
        name  = "configs.secret.argocdServerAdminPassword"
        value = bcrypt_hash.argocd_admin.id
      }
    ]
  }

  # external k3d prod cluster registration
  external_clusters = {
    prod = {
      server     = local.prod_cluster_server # server url of the cluster
      namespaces = [] # or ["apps", "default"] if you want to scope

      config = {
        bearer_token = local.prod_cluster_token # token to authenticate to the cluster
        tls_client_config = {
          ca_data  = local.prod_cluster_ca # CA data of the cluster
          insecure = false
        }
      }

      metadata = {
        labels = {
          environment   = "prod"
          enable_argocd = true
          cluster_name  = "prod"
        }
        annotations = {}
      }
    }
  }

  apps = {
    management = {
      name      = "app-of-apps"
      namespace = "argocd"
      project   = "default"
      sources = [
        {
          repo_url        = "https://github.com/kylerloucks/k8s-workshop-argo-platform.git"
          target_revision = "main"
          path            = "argocd/bootstrap/management"
        }
      ]
      destination_namespace = "argocd"
      destination_server    = "https://kubernetes.default.svc"
      prune                 = true
      self_heal             = true
      sync_options = [
        "CreateNamespace=true",
        "ApplyOutOfSyncOnly=true",
        "PrunePropagationPolicy=foreground",
        "ServerSideApply=true",
      ]
    }
  }

  depends_on = [
    data.kubernetes_secret_v1.argocd_manager_token,
  ]
}
