# Argo CD Image Updater Terraform Module

This module installs [Argo CD Image Updater](https://github.com/argoproj-labs/argocd-image-updater) into a Kubernetes cluster via Helm and can optionally configure AWS IRSA (IAM role for service account) for pulling from registries like ECR.

## Features

- Deploys Argo CD Image Updater using the upstream Helm chart (`argocd-image-updater`).
- Optionally **creates an IAM role for IRSA** and auto-injects the Helm service account annotation:
  - `serviceAccount.annotations.eks.amazonaws.com/role-arn`
- Optionally attaches **default** and/or **custom** IAM policies to the created role.

Inputs are declared in `variables.tf`.

## Install only (no IRSA)

```hcl
module "argocd_image_updater" {
  source = "../modules/argocd-image-updater"

  enable_image_updater = true
  image_updater = {
    namespace        = "argocd"
    create_namespace = true
    chart_version    = "1.0.2"
    repository       = "https://argoproj.github.io/argo-helm"
  }
}
```

## Install + create IAM role (IRSA) and attach default policies

When `image_updater_create_iam_role = true`, the module creates an IAM role + trust policy for the Kubernetes service account and will automatically inject the role annotation into the Helm release.

```hcl
module "argocd_image_updater" {
  source = "../modules/argocd-image-updater"

  enable_image_updater                 = true
  image_updater_create_iam_role        = true
  image_updater_attach_default_policies = true

  # IRSA inputs
  image_updater_irsa_oidc_provider_arn = module.eks.oidc_provider_arn
  image_updater_irsa_oidc_provider_url = module.eks.cluster_oidc_issuer_url

  # Must match the chart's serviceAccount.name if you override it
  image_updater_service_account_name = "argocd-image-updater"

  image_updater = {
    namespace = "argocd"
  }
}
```

## Use an existing IAM role ARN (IRSA)

If you prefer to create IAM resources outside this module, pass an existing role ARN. The module will still auto-inject the Helm annotation.

```hcl
module "argocd_image_updater" {
  source = "../modules/argocd-image-updater"

  image_updater_create_iam_role = false
  image_updater_iam_role_arn = aws_iam_role.argocd_image_updater.arn

  image_updater = {
    namespace = "argocd"
  }
}
```

## Attach custom policies (only when creating the role)

```hcl
module "argocd_image_updater" {
  source = "../modules/argocd-image-updater"

  image_updater_create_iam_role = true

  image_updater_irsa_oidc_provider_arn = module.eks.oidc_provider_arn
  image_updater_irsa_oidc_provider_url = module.eks.cluster_oidc_issuer_url

  # Disable defaults if you want fully custom, least-privilege policies
  image_updater_attach_default_policies = false

  image_updater_additional_policy_arns = {
    fine_grained = aws_iam_policy.my_fine_grained_policy.arn
  }
}
```
