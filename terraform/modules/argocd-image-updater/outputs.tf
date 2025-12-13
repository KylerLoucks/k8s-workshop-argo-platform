output "image_updater" {
  description = "Argo CD Image Updater Helm release (if enabled)"
  value       = try(helm_release.image_updater[0], null)
}

output "image_updater_iam_role_arn" {
  description = "IAM role ARN used for Argo CD Image Updater service account (created by module or provided)"
  value       = local.image_updater_role_arn
}