terraform {
  required_providers {
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "~> 7.0"
    }
  }
}

################################################################################
# Install ArgoCD
################################################################################
resource "helm_release" "argocd" {
  count = var.create && var.install ? 1 : 0

  name             = try(var.argocd.name, "argo-cd")
  description      = try(var.argocd.description, "A Helm chart to install ArgoCD")
  namespace        = try(var.argocd.namespace, "argocd")
  create_namespace = try(var.argocd.create_namespace, true)
  chart            = try(var.argocd.chart, "argo-cd")
  version          = try(var.argocd.chart_version, "9.1.1")
  repository       = try(var.argocd.repository, "https://argoproj.github.io/argo-helm")
  values           = try(var.argocd.values, [])

  timeout                    = try(var.argocd.timeout, null)
  repository_key_file        = try(var.argocd.repository_key_file, null)
  repository_cert_file       = try(var.argocd.repository_cert_file, null)
  repository_ca_file         = try(var.argocd.repository_ca_file, null)
  repository_username        = try(var.argocd.repository_username, null)
  repository_password        = try(var.argocd.repository_password, null)
  devel                      = try(var.argocd.devel, null)
  verify                     = try(var.argocd.verify, null)
  keyring                    = try(var.argocd.keyring, null)
  disable_webhooks           = try(var.argocd.disable_webhooks, null)
  reuse_values               = try(var.argocd.reuse_values, null)
  reset_values               = try(var.argocd.reset_values, null)
  force_update               = try(var.argocd.force_update, null)
  recreate_pods              = try(var.argocd.recreate_pods, null)
  cleanup_on_fail            = try(var.argocd.cleanup_on_fail, null)
  max_history                = try(var.argocd.max_history, null)
  atomic                     = try(var.argocd.atomic, null)
  skip_crds                  = try(var.argocd.skip_crds, null)
  render_subchart_notes      = try(var.argocd.render_subchart_notes, null)
  disable_openapi_validation = try(var.argocd.disable_openapi_validation, null)
  wait                       = try(var.argocd.wait, true)
  wait_for_jobs              = try(var.argocd.wait_for_jobs, null)
  dependency_update          = try(var.argocd.dependency_update, null)
  replace                    = try(var.argocd.replace, null)
  lint                       = try(var.argocd.lint, null)

  postrender    = try(var.argocd.postrender, null)
  set           = try(var.argocd.set, [])
  set_sensitive = try(var.argocd.set_sensitive, [])

}


################################################################################
# In-cluster (management) cluster registration via ArgoCD provider
################################################################################
locals {
  cluster_name = try(var.cluster.cluster_name, "in-cluster")
  environment  = try(var.cluster.environment, "dev")

  argocd_labels = merge(
    {
      cluster_name  = local.cluster_name
      environment   = local.environment
      enable_argocd = true
    },
    try(var.cluster.addons, {})
  )

  argocd_annotations = merge(
    {
      cluster_name = local.cluster_name
      environment  = local.environment
    },
    try(var.cluster.metadata, {})
  )
}

################################################################################
# External clusters registered via ArgoCD provider
################################################################################
resource "argocd_cluster" "external" {
  for_each = var.create ? var.external_clusters : {}

  server = each.value.server
  name   = try(each.value.name, each.key)

  config {
    bearer_token = each.value.bearer_token
    username     = try(each.value.username, null)
    password     = try(each.value.password, null)

    tls_client_config {
      insecure  = try(each.value.insecure, false)
      ca_data   = each.value.ca_data
      cert_data = try(each.value.cert_data, null)
      key_data  = try(each.value.key_data, null)
    }
  }

  metadata {
    labels      = try(each.value.labels, {})
    annotations = try(each.value.annotations, {})
  }

  namespaces  = try(each.value.namespaces, [])
  project     = try(each.value.project, "default")
  shard       = try(each.value.shard, null)
  

  depends_on = [helm_release.argocd]
}