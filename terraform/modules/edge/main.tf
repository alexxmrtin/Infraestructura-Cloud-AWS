data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Buscamos en Route53 el dominio vinculado a la app que se va aejecutar en al infraestructura
data "aws_route53_zone" "this" {
  name         = var.domain_name
  private_zone = false
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  shop_domain = "${var.shop_subdomain}.${var.domain_name}"
  alb_domain  = "${var.alb_subdomain}.${var.domain_name}"
  shop_url    = "https://${local.shop_domain}"
}
