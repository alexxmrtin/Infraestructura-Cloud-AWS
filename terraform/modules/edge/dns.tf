# Este archivo escribe en Route 53 los registros que unen nuestras urls con los servicios de AWS. CloudFront tiene un DNS que le pone AWS (d1234abcd.cloudfront.net) y el ALB otro (...elb.amazonaws.com). Con aws_route53_record.shop hacemos que shop.midominio.com apunte a CloudFront, y con aws_route53_record.alb que alb.midominio.com apunte al ALB. Son registros alias, que siguen al servicio aunque cambien sus IPs.

resource "aws_route53_record" "shop" {
  for_each = toset(["A", "AAAA"])

  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.shop_domain
  type    = each.value

  alias {
    name                   = aws_cloudfront_distribution.shop.domain_name
    zone_id                = aws_cloudfront_distribution.shop.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "alb" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.alb_domain
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}
