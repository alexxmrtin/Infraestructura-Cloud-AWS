variable "name" {
  description = "Prefijo de nombres de los recursos (p. ej. infra-cloud-aws-dev)."
  type        = string
}

variable "domain_name" {
  description = "Dominio comprado en Route 53 (su hosted zone ya existe y no la gestiona Terraform)."
  type        = string
}

variable "shop_subdomain" {
  description = "Subdominio de la tienda: <shop_subdomain>.<domain_name>."
  type        = string
  default     = "shop"
}

variable "alb_subdomain" {
  description = "Subdominio que apunta al ALB; CloudFront lo usa como origen de /api."
  type        = string
  default     = "alb"
}

variable "alb_dns_name" {
  description = "Dirección del ALB (sale del módulo compute)."
  type        = string
}

variable "alb_zone_id" {
  description = "Zona del ALB para el registro alias (sale del módulo compute)."
  type        = string
}

variable "origin_verify_header" {
  description = "Cabecera secreta que CloudFront añade al ir al ALB."
  type        = string
  default     = "X-Origin-Verify"
}

variable "frontend_dir" {
  description = "Carpeta con la web estática que se sube al bucket."
  type        = string
}

variable "auth_domain_prefix" {
  description = "Prefijo del dominio de login de Cognito (<prefijo>.auth.<region>.amazoncognito.com). No puede contener aws, amazon ni cognito."
  type        = string
}

variable "price_class" {
  description = "Ubicaciones de CloudFront: PriceClass_100 (Europa y Norteamérica, la más barata), _200 o _All."
  type        = string
  default     = "PriceClass_100"
}

variable "enable_waf" {
  description = "Poner el WAF delante de CloudFront (unos 8 USD/mes encendido 24/7)."
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Peticiones por IP en 5 minutos antes de que el WAF la bloquee."
  type        = number
  default     = 1000
}

variable "log_retention_days" {
  description = "Días que se guardan los logs de CloudFront y del WAF."
  type        = number
  default     = 7
}
