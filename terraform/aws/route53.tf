# Public Route53 zone for the domain.
# This was created automatically when the domain was registered.
data "aws_route53_zone" "domain" {
  name         = var.domain_name
  private_zone = false
}