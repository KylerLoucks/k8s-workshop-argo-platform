module "argocd" {
  source = "../modules/argocd"

  argocd = {
    chart_version = "9.1.1"

    values = [
      yamlencode({

        # Use externalRedis instead of the in-cluster one
        redis = {
          enabled = false
        }
        redis-ha = {
          enabled = false
        }

        externalRedis = {
          host     = module.argocd_external_redis.replication_group_primary_endpoint_address
          port     = module.argocd_external_redis.replication_group_port
          username = "default"
          # password will be injected via set_sensitive below
          # externalRedis.password
        }


        configs = {
          params = {
            "server.insecure" = true
          }
        }

        # Enable TLS when ArgoCD talks to external Redis. Will cause connection errors if not set.
        controller = {
          extraArgs = [
            "--redis-use-tls",
          ]
        }

        repoServer = {
          extraArgs = [
            "--redis-use-tls",
          ]
        }

        server = {
          extraArgs = [
            "--redis-use-tls",
          ]
          service = { type = "ClusterIP" }

          # Public ALB for webhook only
          ingress = {
            enabled          = true
            ingressClassName = "alb"
            pathType         = "Prefix"
            hosts            = ["*"] # use default hostname for alb
            # hosts            = [for domain in var.delegated_domains : "argocd.${domain}"]
            paths = ["/"]
            annotations = {
              "alb.ingress.kubernetes.io/scheme"       = "internet-facing"
              "alb.ingress.kubernetes.io/target-type"  = "ip"
              "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\":80}]"
              #   "alb.ingress.kubernetes.io/certificate-arn" = [for domain in var.delegated_domains : aws_acm_certificate.argocd[domain].arn]
            }
          }

          # Internal ALB for UI
          #   additionalIngress = [{
          #     name             = "ui-internal"
          #     ingressClassName = "alb"
          #     # hosts            = ["argocd.${local.private_domain}"]
          #     paths            = ["/"]
          #     annotations = {
          #       "alb.ingress.kubernetes.io/scheme"       = "internal"
          #       "alb.ingress.kubernetes.io/target-type"  = "ip"
          #       "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\":80}]"
          #     }
          #   }]
        }
      })
    ]

    set_sensitive = [
      # Argo CD admin password (bcrypt)
      {
        name  = "configs.secret.argocdServerAdminPassword"
        value = bcrypt_hash.argo.id
      },


      # External Redis password from Secrets Manager. Must be plaintext since it's passed to the external Redis.
      {
        name  = "externalRedis.password"
        value = jsondecode(aws_secretsmanager_secret_version.argocd_redis_auth.secret_string)["redis-password"]
      }
    ]
  }

  depends_on = [
    module.eks,
    aws_secretsmanager_secret_version.argocd_redis_auth,
    module.argocd_external_redis
  ]
}