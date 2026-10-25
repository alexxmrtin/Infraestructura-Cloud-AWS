# Las variables del módulo de red: quien lo usa (envs/dev/main.tf)
# los cambia sin tocar el resto del código. Cada variable tiene:
#   description  qué es
#   type         qué dato admite (texto, número, true/false)
#   default      el valor si nadie dice otro (sin default = obligatoria)
#   validation   control de calidad: si el valor no tiene sentido, Terraform
#                se para con el error_message antes de crear nada
#
#   name                      prefijo de los nombres (obligatoria)
#   vpc_cidr, az_count        tamaño del edificio y número de zonas
#   nat_mode, nat_gateway_*,  qué portero usar para salir a Internet
#   nat_instance_type
#   flow_logs_*               cuánto se guardan los logs y si se pueden borrar

variable "name" {
  description = "Prefijo de nombres de los recursos (p. ej. infra-cloud-aws-dev)."
  type        = string
}

variable "vpc_cidr" {
  description = "Rango de IPs de la VPC. Un /16 deja sitio para crecer."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr debe ser un CIDR válido de /20 o más grande."
  }
}

variable "az_count" {
  description = "Número de zonas de disponibilidad (2 en dev; 3 da más resiliencia y más coste)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count debe ser 2 o 3."
  }
}

variable "nat_mode" {
  description = <<-EOT
    Cómo salen a Internet las subredes privadas de aplicación:
      instance = una instancia NAT t4g.nano (barata, sin alta disponibilidad; para dev)
      gateway  = NAT Gateway gestionado por AWS (caro, alta disponibilidad)
      none     = sin salida a Internet (solo VPC endpoints)
  EOT
  type        = string
  default     = "instance"

  validation {
    condition     = contains(["instance", "gateway", "none"], var.nat_mode)
    error_message = "nat_mode debe ser instance, gateway o none."
  }
}

variable "nat_gateway_per_az" {
  description = "Con nat_mode = gateway: un NAT Gateway por AZ (true, para prod) o uno compartido (false)."
  type        = bool
  default     = false
}

variable "nat_instance_type" {
  description = "Tipo de la instancia NAT (ARM/Graviton)."
  type        = string
  default     = "t4g.nano"
}

variable "flow_logs_retention_days" {
  description = "Días que se guardan los Flow Logs en S3 antes de borrarse."
  type        = number
  default     = 30
}

variable "flow_logs_force_destroy" {
  description = "Permite borrar el bucket de Flow Logs aunque tenga objetos (true en dev, para destroy por sesión)."
  type        = bool
  default     = true
}

variable "flow_logs_kms_key_arn" {
  description = "ARN de la clave KMS que cifra el bucket de Flow Logs (sale del módulo security)."
  type        = string
}
