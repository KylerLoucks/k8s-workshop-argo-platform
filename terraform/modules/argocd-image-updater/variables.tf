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

variable "create_role" {
  description = "Whether this module should create an IAM role for the Argo CD Image Updater service account (IRSA). If false, set image_updater_iam_role_arn to use an existing role."
  type        = bool
  default     = false
}

variable "iam_role_arn" {
  description = "Existing IAM role ARN to use for the Argo CD Image Updater service account (IRSA). When set, the module will auto-inject the Helm serviceAccount role annotation."
  type        = string
  default     = null

  validation {
    condition     = var.iam_role_arn == null || can(regex("^arn:aws:iam::", var.iam_role_arn))
    error_message = "iam_role_arn must be a valid IAM role ARN."
  }
}

variable "attach_default_policies" {
  description = "Whether to attach module-provided default IAM policies to the Image Updater role (only applies when image_updater_create_iam_role = true)."
  type        = bool
  default     = true
}

variable "additional_policy_arns" {
  description = "Additional IAM policy ARNs to attach to the Image Updater role (only applies when image_updater_create_iam_role = true). Map keys are arbitrary identifiers."
  type        = map(string)
  default     = {}
}

variable "oidc_providers" {
  description = "Map of OIDC providers where each provider map should contain the `provider`, `provider_arn`, and `namespace_service_accounts`"
  type        = any
  default     = {}
}
variable "tags" {
  description = "AWS resource tags to apply where supported"
  type        = map(string)
  default     = {}
}