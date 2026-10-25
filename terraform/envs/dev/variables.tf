variable "project" {
  description = "Nombre corto del proyecto, prefijo de los recursos."
  type        = string
  default     = "infra-cloud-aws"
}

variable "environment" {
  description = "Nombre del entorno."
  type        = string
  default     = "dev"
}

variable "region" {
  description = "Región de AWS."
  type        = string
  default     = "eu-west-1"
}

# --- Network ---

variable "vpc_cidr" {
  description = "Rango de IPs de la VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Zonas de disponibilidad (2 o 3)."
  type        = number
  default     = 2
}

variable "nat_mode" {
  description = "Salida a Internet de las subredes privadas: instance (barato, dev), gateway (gestionado, caro) o none."
  type        = string
  default     = "instance"
}


# ---Security---

variable "enable_guardduty" {
  description = "Crear GuardDuty (false si la cuenta ya tiene un detector en la región)."
  type        = bool
  default     = true
}

variable "enable_access_analyzer" {
  description = "Crear IAM Access Analyzer (false si la cuenta ya tiene uno en la región)."
  type        = bool
  default     = true
}

variable "enable_cache" {
  description = "Crear ElastiCache Valkey (unos 0,017 USD/hora)."
  type        = bool
  default     = true
}


# ---Computo---

variable "enable_test_client" {
  description = "Crear la instancia de pruebas para conectarse a RDS y Valkey por SSM."
  type        = bool
  default     = false
}

variable "enable_backup" {
  description = "Crear AWS Backup para los discos EBS de las instancias de ECS."
  type        = bool
  default     = true
}


variable "domain_name" {
  description = "Dominio comprado en Route 53. En GitHub va en la variable DOMAIN_NAME; en local, -var o un fichero .auto.tfvars."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+(\\.[a-z0-9-]+)+$", var.domain_name))
    error_message = "Pon el dominio que compraste en Route 53, por ejemplo midominio.com (en GitHub, la variable DOMAIN_NAME)."
  }
}

variable "shop_subdomain" {
  description = "Subdominio de la tienda: <shop_subdomain>.<domain_name>."
  type        = string
  default     = "shop"
}

variable "enable_waf" {
  description = "Poner el WAF delante de CloudFront."
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email que recibe los avisos de la tienda. En GitHub va en la variable NOTIFICATION_EMAIL; vacío = sin emails."
  type        = string
  default     = ""

  validation {
    condition     = var.notification_email == "" || can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", var.notification_email))
    error_message = "Pon un email válido (o déjalo vacío para no recibir avisos)."
  }
}

variable "monthly_budget_usd" {
  description = "Presupuesto mensual en USD de este entorno (avisa por email al 50 %, al 100 % y si la previsión lo supera)."
  type        = number
  default     = 10
}
