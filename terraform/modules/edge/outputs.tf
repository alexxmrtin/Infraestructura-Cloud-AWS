output "shop_url" {
  description = "Dirección de la tienda."
  value       = local.shop_url
}

output "alb_certificate_arn" {
  description = "Certificado validado del ALB (para el listener HTTPS del módulo compute)."
  value       = aws_acm_certificate_validation.alb.certificate_arn
}

output "origin_verify_header" {
  description = "Nombre de la cabecera secreta de CloudFront."
  value       = var.origin_verify_header
}

output "origin_verify_value" {
  description = "Valor de la cabecera secreta de CloudFront."
  value       = random_password.origin_verify.result
  sensitive   = true
}

output "distribution_id" {
  description = "ID de la distribución de CloudFront."
  value       = aws_cloudfront_distribution.shop.id
}

output "distribution_domain_name" {
  description = "Dirección *.cloudfront.net de la distribución."
  value       = aws_cloudfront_distribution.shop.domain_name
}

output "frontend_bucket" {
  description = "Bucket con la web estática."
  value       = aws_s3_bucket.frontend.bucket
}

output "user_pool_id" {
  description = "User pool de Cognito."
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_client_id" {
  description = "Cliente de la web en Cognito."
  value       = aws_cognito_user_pool_client.web.id
}

output "login_url" {
  description = "Página de login de Cognito."
  value       = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${local.region}.amazoncognito.com/login?client_id=${aws_cognito_user_pool_client.web.id}&response_type=code&scope=openid+email+profile&redirect_uri=${urlencode("${local.shop_url}/")}"
}

output "web_acl_arn" {
  description = "WAF de CloudFront (null si está apagado)."
  value       = try(aws_wafv2_web_acl.shop[0].arn, null)
}

output "web_acl_name" {
  description = "Nombre del WAF (null si está apagado), para las métricas del dashboard."
  value       = try(aws_wafv2_web_acl.shop[0].name, null)
}

output "cloudfront_log_group_name" {
  description = "Log group de us-east-1 con cada petición a CloudFront."
  value       = aws_cloudwatch_log_group.cloudfront.name
}

output "waf_log_group_name" {
  description = "Log group de us-east-1 con las peticiones que bloquea el WAF (null si está apagado)."
  value       = try(aws_cloudwatch_log_group.waf[0].name, null)
}
