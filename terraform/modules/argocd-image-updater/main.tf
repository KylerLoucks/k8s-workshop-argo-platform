data "aws_caller_identity" "current" {
  count = local.create_role ? 1 : 0
}
data "aws_partition" "current" {
  count = local.create_role ? 1 : 0
}

################################################################################
# ArgoCD Image Updater
################################################################################
locals {
  create_role = var.create && var.create_role

  # Chart-derived defaults
  image_updater_namespace = try(var.image_updater.namespace, "argocd")

  # IAM naming
  iam_role_name = coalesce(try(var.image_updater.iam_role_name, null), "argocd-image-updater")

  account_id = try(data.aws_caller_identity.current[0].account_id, "*")
  partition  = try(data.aws_partition.current[0].partition, "*")

  iam_role_policy_prefix = "arn:${local.partition}:iam::aws:policy"

  # Canonical role ARN (created or provided)
  image_updater_role_arn = coalesce(one(aws_iam_role.image_updater[*].arn), var.iam_role_arn)

  attach_default_image_updater_policies = local.create_role && var.attach_default_policies

  image_updater_iam_role_policies = { for k, v in {
    AmazonEC2ContainerRegistryReadOnly = "${local.iam_role_policy_prefix}/AmazonEC2ContainerRegistryReadOnly",
  } : k => v if local.attach_default_image_updater_policies }

  image_updater_irsa_set = local.image_updater_role_arn != null ? [
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = local.image_updater_role_arn
    }
  ] : []
}

data "aws_iam_policy_document" "image_updater_assume_role_policy" {
  count = local.create_role ? 1 : 0

  dynamic "statement" {
    for_each = var.oidc_providers

    content {
      effect  = "Allow"
      actions = ["sts:AssumeRoleWithWebIdentity"]

      principals {
        type        = "Federated"
        identifiers = [statement.value.provider_arn]
      }

      condition {
        test     = "StringEquals"
        variable = "${replace(statement.value.provider_arn, "/^(.*provider/)/", "")}:sub"
        values   = [for sa in statement.value.namespace_service_accounts : "system:serviceaccount:${sa}"]
      }

      # https://aws.amazon.com/premiumsupport/knowledge-center/eks-troubleshoot-oidc-and-irsa/?nc1=h_ls
      condition {
        test     = "StringEquals"
        variable = "${replace(statement.value.provider_arn, "/^(.*provider/)/", "")}:aud"
        values   = ["sts.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role" "image_updater" {
  count = local.create_role ? 1 : 0

  name        = try(var.image_updater.iam_role_use_name_prefix, false) ? null : local.iam_role_name
  name_prefix = try(var.image_updater.iam_role_use_name_prefix, false) ? "${local.iam_role_name}-" : null
  path        = coalesce(try(var.image_updater.iam_role_path, null), "/")
  description = coalesce(try(var.image_updater.iam_role_description, null), "IRSA role for Argo CD Image Updater")

  assume_role_policy    = data.aws_iam_policy_document.image_updater_assume_role_policy[0].json
  permissions_boundary  = try(var.image_updater.iam_role_permissions_boundary, null)
  force_detach_policies = true

  tags = var.tags
}

# Policies attached ref https://docs.aws.amazon.com/eks/latest/userguide/service_IAM_role.html
resource "aws_iam_role_policy_attachment" "image_updater_default" {
  for_each = local.create_role ? local.image_updater_iam_role_policies : {}

  policy_arn = each.value
  role       = aws_iam_role.image_updater[0].name
}

resource "aws_iam_role_policy_attachment" "image_updater_additional" {
  for_each = local.create_role ? var.additional_policy_arns : {}

  policy_arn = each.value
  role       = aws_iam_role.image_updater[0].name
}

resource "helm_release" "image_updater" {
  count = var.create ? 1 : 0

  name             = try(var.image_updater.name, "argocd-image-updater")
  description      = try(var.image_updater.description, "A Helm chart to install ArgoCD Image Updater")
  namespace        = try(var.image_updater.namespace, "argocd")
  create_namespace = try(var.image_updater.create_namespace, true)
  chart            = try(var.image_updater.chart, "argocd-image-updater")
  version          = try(var.image_updater.chart_version, "1.0.2")
  repository       = try(var.image_updater.repository, "https://argoproj.github.io/argo-helm")
  values           = try(var.image_updater.values, [])

  timeout                    = try(var.image_updater.timeout, null)
  repository_key_file        = try(var.image_updater.repository_key_file, null)
  repository_cert_file       = try(var.image_updater.repository_cert_file, null)
  repository_ca_file         = try(var.image_updater.repository_ca_file, null)
  repository_username        = try(var.image_updater.repository_username, null)
  repository_password        = try(var.image_updater.repository_password, null)
  devel                      = try(var.image_updater.devel, null)
  verify                     = try(var.image_updater.verify, null)
  keyring                    = try(var.image_updater.keyring, null)
  disable_webhooks           = try(var.image_updater.disable_webhooks, null)
  reuse_values               = try(var.image_updater.reuse_values, null)
  reset_values               = try(var.image_updater.reset_values, null)
  force_update               = try(var.image_updater.force_update, null)
  recreate_pods              = try(var.image_updater.recreate_pods, null)
  cleanup_on_fail            = try(var.image_updater.cleanup_on_fail, null)
  max_history                = try(var.image_updater.max_history, null)
  atomic                     = try(var.image_updater.atomic, null)
  skip_crds                  = try(var.image_updater.skip_crds, null)
  render_subchart_notes      = try(var.image_updater.render_subchart_notes, null)
  disable_openapi_validation = try(var.image_updater.disable_openapi_validation, null)
  wait                       = try(var.image_updater.wait, true)
  wait_for_jobs              = try(var.image_updater.wait_for_jobs, null)
  dependency_update          = try(var.image_updater.dependency_update, null)
  replace                    = try(var.image_updater.replace, null)
  lint                       = try(var.image_updater.lint, null)


  postrender    = try(var.image_updater.postrender, null)
  set           = concat(local.image_updater_irsa_set, try(var.image_updater.set, []))
  set_sensitive = try(var.image_updater.set_sensitive, [])
}