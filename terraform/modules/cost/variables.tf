variable "name" {
  description = "Prefijo de nombres de los recursos (p. ej. infra-cloud-aws-dev)."
  type        = string
}

variable "project" {
  description = "Valor de la etiqueta Project (la ponen los default_tags del provider)."
  type        = string
}

variable "environment" {
  description = "Valor de la etiqueta Environment (la ponen los default_tags del provider)."
  type        = string
}

variable "notification_email" {
  description = "Email que recibe el presupuesto y las anomalías de coste. Vacío = no se crean."
  type        = string
  default     = ""
}

variable "notification_topic_arn" {
  description = "Tema SNS de avisos de la tienda, donde llega el recordatorio de apagado (sale del módulo serverless)."
  type        = string
}

variable "data_kms_key_arn" {
  description = "Clave KMS con la que está cifrado el tema de avisos (sale del módulo security)."
  type        = string
}

variable "monthly_budget_usd" {
  description = "Límite mensual en USD de lo que gasta este entorno (solo lo etiquetado con Project y Environment)."
  type        = number
  default     = 10
}

variable "anomaly_threshold_usd" {
  description = "Impacto en USD a partir del cual una anomalía de coste manda email."
  type        = number
  default     = 3
}

variable "enable_reminder" {
  description = "Mandar cada noche un aviso al tema de avisos mientras el entorno siga encendido."
  type        = bool
  default     = true
}

variable "reminder_schedule" {
  description = "Cuándo llega el recordatorio de apagado (expresión de EventBridge Scheduler)."
  type        = string
  default     = "cron(0 22 * * ? *)"
}

variable "schedule_timezone" {
  description = "Zona horaria del recordatorio."
  type        = string
  default     = "Europe/Madrid"
}

variable "daily_cost_usd" {
  description = "Coste aproximado por día con todo encendido, solo para el texto del recordatorio."
  type        = number
  default     = 4
}
