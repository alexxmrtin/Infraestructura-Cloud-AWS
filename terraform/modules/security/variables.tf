variable "name" {
  description = "Prefijo de nombres de los recursos (p. ej. infra-cloud-aws-dev)."
  type        = string
}

variable "kms_deletion_window_days" {
  description = "Días que una clave KMS queda pendiente de borrado tras el destroy (7-30). No se cobra en ese tiempo."
  type        = number
  default     = 7

  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "kms_deletion_window_days debe estar entre 7 y 30."
  }
}

variable "cloudtrail_retention_days" {
  description = "Días que se guardan los ficheros de CloudTrail en S3."
  type        = number
  default     = 90
}

variable "force_destroy" {
  description = "Permite borrar el bucket de CloudTrail aunque tenga ficheros (true en dev, para destroy por sesión)."
  type        = bool
  default     = true
}

variable "enable_guardduty" {
  description = "Crear el detector de GuardDuty (false si la cuenta ya tiene uno en esta región)."
  type        = bool
  default     = true
}

variable "enable_access_analyzer" {
  description = "Crear IAM Access Analyzer de cuenta (false si ya existe uno en esta región)."
  type        = bool
  default     = true
}
