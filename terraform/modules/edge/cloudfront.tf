# Cloudfront es un servicio de aws que se encarga de servir a clientes recursos en nuestro entorno aws, en mi caso sirve contenido desde un bucket S3 y el ALB de la VPC. Usamos Cloudfront y los edge points para maximizar la latencia y hacer que el uso, en este caso, de la web sea lo mas rapido posible


# Lo primero es establecer 3 politicas de aws,no creadas por mi. "CachingOptimized" para guardar en cache de cloudfront lo mas rapido posible, "AllViewerExceptHost" para reenviar al ALB todo lo que manda el navegador y "SecurityHeaderPolicy" para añadir cabeceras de seguridad como usar el protocolo https unicamente y asegurarnos de que no puede haber un man in the middle o cosas por el estilo
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

data "aws_cloudfront_response_headers_policy" "security" {
  name = "Managed-SecurityHeadersPolicy"
}

# Esta es otra politica de cache pero para la API, la creo yo. Sirve para que cloudfront no guarde nada de la API en cache y ademas que Cloudfront pueda reenviar el token de la API.
resource "aws_cloudfront_cache_policy" "api" {
  name        = "${var.name}-api"
  comment     = "API sin cache; Authorization llega al ALB"
  min_ttl     = 0
  default_ttl = 0
  max_ttl     = 1

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = false
    enable_accept_encoding_brotli = false

    headers_config {
      header_behavior = "whitelist"

      headers {
        items = ["Authorization"]
      }
    }

    query_strings_config {
      query_string_behavior = "all"
    }

    cookies_config {
      cookie_behavior = "none"
    }
  }
}

# Este recurso de aws permite a Cloudfront pedir ficheros al bucket.Recordemos que el bucket S3 la configuramos para que no se pudiera acceder publicamente, necesitamos esto para que clodufront pueda acceder desde fuera.
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.name}-frontend"
  description                       = "CloudFront firma las peticiones al bucket de la web"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Ademas de el bloque que acabamos de ver, necesitamos establecer una contraseña, es basicamente una prueba criptografica con el que vamos a firmar las peticiones que vamos a hacer a S3. El bloque anterior creamos el mecanismo de firma para verificar a cloudfront, y este bloque es el como lo verificamos.
resource "random_password" "origin_verify" {
  length  = 32
  special = false
}


# Y ya por ultimo este bloque crea el servicio de Cloudfront en la cuenta aws, el primer bloque son configuraciones generales, el segundo bloque son los origenes, es decir, el alb y el bucket, y el tercer bloque son como se va a comportar cloudfront dependiendo de el origen que se use.
resource "aws_cloudfront_distribution" "shop" {
  # checkov:skip=CKV_AWS_86:El registro de accesos va con la versión nueva (entrega de logs a CloudWatch, logs.tf); checkov solo mira logging_config, la versión antigua con ACL.
  # checkov:skip=CKV_AWS_310:Un solo origen por ruta; sin grupo de failover en dev.
  # checkov:skip=CKV_AWS_374:Sin restricción por países: la tienda es pública.
  # checkov:skip=CKV2_AWS_47:El WAF lleva AWSManagedRulesKnownBadInputsRuleSet (Log4j); checkov no lo ve por el count de enable_waf.
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  comment             = "${var.name}: web en S3 y /api en el ALB"
  aliases             = [local.shop_domain]
  default_root_object = "index.html"
  price_class         = var.price_class
  web_acl_id          = var.enable_waf ? aws_wafv2_web_acl.shop[0].arn : null

  origin {
    origin_id                = "frontend"
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  origin {
    origin_id   = "api"
    domain_name = local.alb_domain

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 30
    }

    custom_header {
      name  = var.origin_verify_header
      value = random_password.origin_verify.result
    }
  }

  default_cache_behavior {
    target_origin_id           = "frontend"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id
  }

  ordered_cache_behavior {
    path_pattern               = "/api/*"
    target_origin_id           = "api"
    viewer_protocol_policy     = "https-only"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.api.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.shop.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = { Name = "${var.name}-shop" }
}
