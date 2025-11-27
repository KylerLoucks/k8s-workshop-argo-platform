################################################################################
# ArgoCD Redis Auth credentials with Secrets Manager
################################################################################
resource "random_password" "argocd_redis_auth_password" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "argocd_redis_auth" {
  name                    = "argocd-redis-auth"
	recovery_window_in_days = 0 # Set to zero to force delete during Terraform destroy
  description             = "Auth token for ArgoCD Redis"


  #   kms_key_id = module.kms.ssm_key_id

  tags = {
    Environment = var.environment
    Owner       = var.environment
    ManagedBy   = "terraform"
    SecretType  = "redis-auth"
  }
}

resource "aws_secretsmanager_secret_version" "argocd_redis_auth" {
  secret_id = aws_secretsmanager_secret.argocd_redis_auth.id
  secret_string = jsonencode({
    redis-password = random_password.argocd_redis_auth_password.result
    redis-username = "default"
  })
}




################################################################################
# ArgoCD Admin Password credentials with Secrets Manager
# Login to AWS Secrets manager to extract the ArgoCD admin password with the secret name as "argocd"
################################################################################

resource "random_password" "argocd" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "argocd" {
  name                    = "argocd"
  recovery_window_in_days = 0 # Set to zero to force delete during Terraform destroy
  description             = "ArgoCD admin password"
  tags = {
    Environment = var.environment
    Owner       = var.environment
    ManagedBy   = "terraform"
    SecretType  = "argocd-password"
  }
}

# Argo requires the password to be bcrypt, we use custom provider of bcrypt,
# as the default bcrypt function generates diff for each terraform plan
resource "bcrypt_hash" "argo" {
  cleartext = random_password.argocd.result
}

resource "aws_secretsmanager_secret_version" "argocd" {
  secret_id     = aws_secretsmanager_secret.argocd.id
  secret_string = random_password.argocd.result

  lifecycle {
    # Avoid re-hashing/re-writing on future applies
    ignore_changes = [secret_string]
  }
}