# # Generate a strong random password for Grafana admin
# resource "random_password" "grafana_admin" {
#   length  = 24
#   special = true
# }


# # Create the AWS Secrets Manager secret (metadata)
# resource "aws_secretsmanager_secret" "grafana_admin" {
#   name                    = "grafana/admin-password" # <-- this must match "key" in ExternalSecret
#   recovery_window_in_days = 0                        # Set to zero to force delete during Terraform destroy
#   description             = "Grafana admin password"
#   tags = {
#     Environment = var.environment
#     Owner       = var.environment
#     ManagedBy   = "terraform"
#     SecretType  = "grafana-admin-password"
#   }
# }

# # Store the actual secret value as JSON in SM
# resource "aws_secretsmanager_secret_version" "grafana_admin" {
#   secret_id = aws_secretsmanager_secret.grafana_admin.id

#   secret_string = jsonencode({
#     admin-user     = "admin"
#     admin-password = random_password.grafana_admin.result
#   })
# }


# ################################################################################
# # ACM Certificate for the domain
# ################################################################################
# resource "aws_acm_certificate" "grafana" {
#   domain_name       = "grafana.${var.domain_name}" # e.g. grafana.devawskloucks.click
#   validation_method = "DNS"

#   lifecycle {
#     create_before_destroy = true
#   }
# }

# resource "aws_route53_record" "grafana_validation" {
#   zone_id = data.aws_route53_zone.domain.id
#   name    = tolist(aws_acm_certificate.grafana.domain_validation_options)[0].resource_record_name
#   type    = tolist(aws_acm_certificate.grafana.domain_validation_options)[0].resource_record_type
#   records = [tolist(aws_acm_certificate.grafana.domain_validation_options)[0].resource_record_value]
#   ttl     = 60
# }

# resource "aws_acm_certificate_validation" "grafana" {
#   certificate_arn         = aws_acm_certificate.grafana.arn
#   validation_record_fqdns = [aws_route53_record.grafana_validation.fqdn]
# }

# ################################################################################
# # Install kube-prometheus-stack to manage Prometheus and Grafana
# ################################################################################
# resource "helm_release" "kube-prometheus-stack" {
#   name             = "kube-prometheus-stack"
#   repository       = "https://prometheus-community.github.io/helm-charts"
#   chart            = "kube-prometheus-stack"
#   version          = "79.9.0"
#   create_namespace = true
#   namespace        = "monitoring"
#   values = [
#     yamlencode({
#       grafana = {
#         enabled = true
#         service = {
#           type = "ClusterIP"
#         }
#         ingress = {
#           enabled          = true
#           ingressClassName = "alb"
#           hosts            = ["grafana.${var.domain_name}"]
#           paths            = ["/"]
#           annotations = {
#             "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
#             "alb.ingress.kubernetes.io/target-type"      = "ip"
#             "alb.ingress.kubernetes.io/healthcheck-path" = "/api/health"
#             "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTPS\":443}]"
#             "alb.ingress.kubernetes.io/certificate-arn"  = aws_acm_certificate.grafana.arn
#             # "alb.ingress.kubernetes.io/ssl-redirect" 		= "true"
#             # External DNS annotation to allow external-dns to manage the DNS record
#             "external-dns.alpha.kubernetes.io/hostname" = "grafana.${var.domain_name}"
#           }
#         }
#       }
#       prometheus = {
#         prometheusSpec = {
#           retention                               = "5d"
#           scrapeInterval                          = "30s"
#           serviceMonitorSelectorNilUsesHelmValues = false
#           podMonitorSelectorNilUsesHelmValues     = false

#           # EXPLICITLY no storage PVC (use emptyDir) because we are on fargate and we don't want to pay for storage.
#           storageSpec = {}

#           # Prometheus resources
#           resources = {
#             requests = {
#               cpu    = "500m"
#               memory = "1Gi"
#             }
#             limits = {
#               cpu    = "1"
#               memory = "2Gi"
#             }
#           }

#           # Make the probes much more lenient to allow for slow startup
#           readinessProbe = {
#             httpGet = {
#               path = "/-/ready"
#               port = 9090
#             }
#             initialDelaySeconds = 60
#             timeoutSeconds      = 30
#             periodSeconds       = 10
#             failureThreshold    = 60
#           }

#           livenessProbe = {
#             httpGet = {
#               path = "/-/healthy"
#               port = 9090
#             }
#             initialDelaySeconds = 120
#             timeoutSeconds      = 30
#             periodSeconds       = 10
#             failureThreshold    = 30
#           }

#           startupProbe = {
#             httpGet = {
#               path = "/-/ready"
#               port = 9090
#             }
#             # Allow a *long* startup window before we start killing it
#             initialDelaySeconds = 0
#             timeoutSeconds      = 30
#             periodSeconds       = 10
#             failureThreshold    = 60
#           }
#           # additionalScrapeConfigs = [
#           #   {
#           #     job_name = "kubecost"
#           #     honor_labels = true
#           #     scrape_interval = "1m"
#           #     metrics_path = "/metrics"
#           #   }
#           # ]
#         }
#       }
#     }),
#   ]

#   set_sensitive = [
#     {
#       name  = "grafana.adminPassword"
#       value = random_password.grafana_admin.result
#     },
#     {
#       name  = "grafana.adminUser"
#       value = "admin"
#     }
#   ]

#   depends_on = [
#     module.eks
#   ]
# }
