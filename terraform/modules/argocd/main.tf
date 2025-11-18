terraform {
  required_providers {
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "~> 7.11"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

################################################################################
# Install ArgoCD
################################################################################
resource "helm_release" "argocd" {
  count = var.create ? 1 : 0

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

  namespaces = try(each.value.namespaces, [])
  project    = try(each.value.project, "default")
  shard      = try(each.value.shard, null)


  depends_on = [helm_release.argocd]
}



################################################################################
# App of Apps
################################################################################
resource "argocd_application" "app_of_apps" {
  for_each = var.create ? var.apps : {}

  metadata {
    name        = try(each.value.name, each.key)
    namespace   = try(each.value.namespace, "argocd")
    labels      = try(each.value.labels, {})
    annotations = try(each.value.annotations, {})
  }

  spec {
    project = try(each.value.project, "default")
    dynamic "source" {
      for_each = length(try(each.value.sources, [])) > 0 ? each.value.sources : [
        merge(
          {
            repo_url        = each.value.repo_url
            target_revision = try(each.value.target_revision, "main")
            path            = try(each.value.path, null)
            chart           = try(each.value.chart, null)
            ref             = try(each.value.ref, null)
            name            = try(each.value.source_name, null)
          },
          try(each.value.source, {})
        )
      ]

      content {
        repo_url        = source.value.repo_url
        target_revision = try(source.value.target_revision, try(each.value.target_revision, "main"))
        path            = try(source.value.path, null)
        chart           = try(source.value.chart, null)
        ref             = try(source.value.ref, null)
        name            = try(source.value.name, null)

        dynamic "helm" {
          for_each = lookup(source.value, "helm", null) == null ? [] : [lookup(source.value, "helm", null)]
          content {
            release_name               = try(helm.value.release_name, null)
            version                    = try(helm.value.version, null)
            pass_credentials           = try(helm.value.pass_credentials, null)
            skip_crds                  = try(helm.value.skip_crds, null)
            ignore_missing_value_files = try(helm.value.ignore_missing_value_files, null)
            value_files                = try(helm.value.value_files, null)
            values                     = try(helm.value.values, null)

            dynamic "parameter" {
              for_each = try(helm.value.parameters, [])
              content {
                name         = try(parameter.value.name, null)
                value        = try(parameter.value.value, null)
                force_string = try(parameter.value.force_string, null)
              }
            }

            dynamic "file_parameter" {
              for_each = try(helm.value.file_parameters, [])
              content {
                name = try(file_parameter.value.name, null)
                path = try(file_parameter.value.path, null)
              }
            }
          }
        }

        dynamic "kustomize" {
          for_each = lookup(source.value, "kustomize", null) == null ? [] : [lookup(source.value, "kustomize", null)]
          content {
            name_prefix        = try(kustomize.value.name_prefix, null)
            name_suffix        = try(kustomize.value.name_suffix, null)
            version            = try(kustomize.value.version, null)
            common_labels      = try(kustomize.value.common_labels, null)
            common_annotations = try(kustomize.value.common_annotations, null)
            images             = try(kustomize.value.images, null)
          }
        }
      }
    }
    destination {
      server    = try(each.value.destination_server, null)
      namespace = try(each.value.destination_namespace, "argocd")
      name      = try(each.value.destination_name, null)
    }
    sync_policy {
      automated {
        prune     = try(each.value.prune, true)
        self_heal = try(each.value.self_heal, true)
      }
      sync_options = try(each.value.sync_options, ["CreateNamespace=true", "ApplyOutOfSyncOnly=true", "PrunePropagationPolicy=foreground"])
    }
    dynamic "ignore_difference" {
      for_each = try(each.value.ignore_differences, {})
      content {
        group         = try(ignore_difference.value.group, null)
        kind          = try(ignore_difference.value.kind, null)
        name          = try(ignore_difference.value.name, null)
        namespace     = try(ignore_difference.value.namespace, null)
        json_pointers = try(ignore_difference.value.json_pointers, null)
      }
    }
  }

  depends_on = [helm_release.argocd]
}