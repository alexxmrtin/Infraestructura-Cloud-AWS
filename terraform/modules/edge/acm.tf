# Este codigo se encarga de conseguir dos certificados. Estos certificados son para verificar que nuestros dominios son verdaderos, es decir, que el dominio de el frontend que se sirve desde un bucket S3, y el dominio del ALB de la VPC para conectarse a la API y acceder o modificar datos en la base de datos.

# Creamos dos certificados TLS para que cloudfront pueda conectarse a estos dos recurso y servir el contenido en los edge points.


# Pedimos los certificados,uno "shop" para el bucket S3 y otro alb para la VPC
resource "aws_acm_certificate" "shop" {
  provider = aws.us_east_1

  domain_name       = local.shop_domain
  validation_method = "DNS"

  tags = { Name = "${var.name}-shop" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "alb" {
  domain_name       = local.alb_domain
  validation_method = "DNS"

  tags = { Name = "${var.name}-alb" }

  lifecycle {
    create_before_destroy = true
  }
}

# Una vez pedidos, ACM necesita que creemos dos registros DNS para que ACM compruebe que el dominio es mio. Esto basicamente lo que hace es preparar una lista que usaremos a continuacion para insertas los dos registros
locals {
  validation_records = merge(
    { for o in aws_acm_certificate.shop.domain_validation_options : o.domain_name => o },
    { for o in aws_acm_certificate.alb.domain_validation_options : o.domain_name => o },
  )
}

# Y aqui insertamos los registros en Route53
resource "aws_route53_record" "validation" {
  for_each = local.validation_records

  zone_id         = data.aws_route53_zone.this.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 300
  allow_overwrite = true
}


# Por ultimo estos dos crea los certificados (en realidad lo unico que hace es hacer esperar a clodufront y no usar un certificado que no se ha comprobado)
resource "aws_acm_certificate_validation" "shop" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.shop.arn
  validation_record_fqdns = [aws_route53_record.validation[local.shop_domain].fqdn]
}

resource "aws_acm_certificate_validation" "alb" {
  certificate_arn         = aws_acm_certificate.alb.arn
  validation_record_fqdns = [aws_route53_record.validation[local.alb_domain].fqdn]
}
