locals {
  domain_name = "devawskloucks.click"
}

# Public Route53 zone for the domain.
# This was created automatically when the domain was registered.
data "aws_route53_zone" "domain" {
  name         = local.domain_name
  private_zone = false
}

################################################################################
# ACM Certificate for the domain
################################################################################
resource "aws_acm_certificate" "argocd" {
  domain_name       = "argocd.${local.domain_name}" # e.g. argocd.devawskloucks.click
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "argocd_validation" {
  zone_id = data.aws_route53_zone.domain.id
  name    = tolist(aws_acm_certificate.argocd.domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.argocd.domain_validation_options)[0].resource_record_type
  records = [tolist(aws_acm_certificate.argocd.domain_validation_options)[0].resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "argocd" {
  certificate_arn         = aws_acm_certificate.argocd.arn
  validation_record_fqdns = [aws_route53_record.argocd_validation.fqdn]
}