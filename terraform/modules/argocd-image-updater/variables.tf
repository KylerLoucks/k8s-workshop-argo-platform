variable "create" {
  description = "Create terraform resources"
  type        = bool
  default     = true
}

variable "image_updater" {
  description = "argocd image updater helm options"
  type        = any
  default     = {}
}

variable "image_updater_create_iam_role" {
  description = "Whether this module should create an IAM role for the Argo CD Image Updater service account (IRSA). If false, set image_updater_iam_role_arn to use an existing role."
  type        = bool
  default     = false
}

variable "image_updater_iam_role_arn" {
  description = "Existing IAM role ARN to use for the Argo CD Image Updater service account (IRSA). When set, the module will auto-inject the Helm serviceAccount role annotation."
  type        = string
  default     = null

  validation {
    condition     = var.image_updater_iam_role_arn == null || can(regex("^arn:aws:iam::", var.image_updater_iam_role_arn))
    error_message = "image_updater_iam_role_arn must be a valid IAM role ARN."
  }
}

variable "image_updater_attach_default_policies" {
  description = "Whether to attach module-provided default IAM policies to the Image Updater role (only applies when image_updater_create_iam_role = true)."
  type        = bool
  default     = true
}

variable "image_updater_additional_policy_arns" {
  description = "Additional IAM policy ARNs to attach to the Image Updater role (only applies when image_updater_create_iam_role = true). Map keys are arbitrary identifiers."
  type        = map(string)
  default     = {}
}

variable "image_updater_irsa_oidc_provider_arn" {
  description = "EKS OIDC provider ARN used for IRSA trust policy when creating the Image Updater IAM role (required when image_updater_create_iam_role = true)."
  type        = string
  default     = null

  validation {
    condition     = !var.image_updater_create_iam_role || var.image_updater_irsa_oidc_provider_arn != null
    error_message = "image_updater_irsa_oidc_provider_arn must be set when image_updater_create_iam_role = true."
  }
}

variable "image_updater_irsa_oidc_provider_url" {
  description = "EKS OIDC issuer URL (e.g. https://oidc.eks.<region>.amazonaws.com/id/XXXX) used for IRSA trust policy conditions when creating the Image Updater IAM role (required when image_updater_create_iam_role = true)."
  type        = string
  default     = null

  validation {
    condition     = !var.image_updater_create_iam_role || var.image_updater_irsa_oidc_provider_url != null
    error_message = "image_updater_irsa_oidc_provider_url must be set when image_updater_create_iam_role = true."
  }
}

variable "image_updater_service_account_name" {
  description = "Kubernetes service account name used by Argo CD Image Updater. Must match the Helm chart's serviceAccount name if you override it."
  type        = string
  default     = "argocd-image-updater"
}


variable "tags" {
  description = "AWS resource tags to apply where supported"
  type        = map(string)
  default     = {}
}

variable "prefix_separator" {
  description = "Separator used between name and prefix when use_name_prefix is enabled"
  type        = string
  default     = "-"
}

variable "iam_role_tags" {
  description = "Additional tags applied to IAM roles created by this module"
  type        = map(string)
  default     = {}
}