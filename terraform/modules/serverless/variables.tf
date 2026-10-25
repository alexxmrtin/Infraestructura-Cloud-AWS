variable "name" {
  description = "Prefijo de nombres de los recursos (p. ej. infra-cloud-aws-dev)."
  type        = string
}

variable "data_kms_key_arn" {
  description = "Clave KMS data: tablas, temas SNS y colas SQS (sale del módulo security)."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "Clave KMS logs: logs de las Lambdas, de Step Functions y de API Gateway (sale del módulo security)."
  type        = string
}

variable "lambdas_dir" {
  description = "Carpeta con el código de las Lambdas (una subcarpeta por función)."
  type        = string
}

variable "carts_stream_arn" {
  description = "Stream de la tabla de carritos (sale del módulo data)."
  type        = string
}

variable "invoices_bucket_name" {
  description = "Bucket donde se guardan las facturas (sale del módulo data)."
  type        = string
}

variable "invoices_bucket_arn" {
  description = "ARN del bucket de facturas."
  type        = string
}

variable "notification_email" {
  description = "Email que recibe los avisos de la tienda (pedidos, carritos abandonados, resumen diario). Vacío = sin suscripción."
  type        = string
  default     = ""
}

variable "metrics_namespace" {
  description = "Namespace de CloudWatch de las métricas propias de la tienda (pedidos, importe, rechazos)."
  type        = string
  default     = "ShopFlow"
}

variable "payment_limit" {
  description = "Importe en EUR a partir del cual el cobro simulado se rechaza (para probar el camino de error)."
  type        = number
  default     = 200
}

variable "seed_product_ids" {
  description = "Productos a los que se les pone stock inicial (los cinco que crea la API al arrancar)."
  type        = list(number)
  default     = [1, 2, 3, 4, 5]
}

variable "initial_stock" {
  description = "Unidades iniciales de cada producto."
  type        = number
  default     = 20
}

variable "lambda_timeout" {
  description = "Segundos máximos de cada Lambda."
  type        = number
  default     = 10
}

variable "queue_max_receive_count" {
  description = "Intentos de cada mensaje antes de ir a la cola de errores (DLQ)."
  type        = number
  default     = 3
}

variable "partners_rate_limit" {
  description = "Peticiones por segundo que puede hacer cada partner."
  type        = number
  default     = 5
}

variable "partners_burst_limit" {
  description = "Pico de peticiones simultáneas de cada partner."
  type        = number
  default     = 10
}

variable "partners_daily_quota" {
  description = "Peticiones al día de cada partner."
  type        = number
  default     = 1000
}

variable "daily_report_schedule" {
  description = "Cuándo se manda el resumen diario (expresión cron de EventBridge Scheduler)."
  type        = string
  default     = "cron(0 8 * * ? *)"
}

variable "schedule_timezone" {
  description = "Zona horaria del resumen diario."
  type        = string
  default     = "Europe/Madrid"
}

variable "log_retention_days" {
  description = "Días que se guardan los logs en CloudWatch."
  type        = number
  default     = 7
}

variable "force_destroy" {
  description = "Permite borrar las tablas con datos (true en dev)."
  type        = bool
  default     = true
}
