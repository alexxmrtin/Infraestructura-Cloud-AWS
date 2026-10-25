variable "name" {
  description = "Prefijo de nombres de los recursos (p. ej. infra-cloud-aws-dev). También es el valor de la dimensión Environment de las métricas propias."
  type        = string
}

variable "metrics_namespace" {
  description = "Namespace de CloudWatch donde las Lambdas publican las métricas de la tienda."
  type        = string
  default     = "ShopFlow"
}

variable "alarm_topic_arn" {
  description = "Tema SNS al que avisan las alarmas (el de avisos de la tienda, sale del módulo serverless)."
  type        = string
}

variable "alb_arn_suffix" {
  description = "Final del ARN del ALB (sale del módulo compute)."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Final del ARN del target group de la API (sale del módulo compute)."
  type        = string
}

variable "ecs_cluster_name" {
  description = "Cluster de ECS (sale del módulo compute)."
  type        = string
}

variable "ecs_service_name" {
  description = "Servicio de ECS de la API (sale del módulo compute)."
  type        = string
}

variable "db_instance_id" {
  description = "Instancia de RDS (sale del módulo data)."
  type        = string
}

variable "state_machine_arn" {
  description = "Step Functions del pedido (sale del módulo serverless)."
  type        = string
}

variable "lambda_function_names" {
  description = "Nombre de cada Lambda (sale del módulo serverless)."
  type        = map(string)
}

variable "lambda_log_group_names" {
  description = "Log group de cada Lambda (sale del módulo serverless)."
  type        = map(string)
}

variable "alarmed_lambdas" {
  description = "Lambdas con alarma de errores. payment y stock no la llevan: sus errores son pedidos rechazados (sin dinero o sin stock), no fallos."
  type        = list(string)
  default     = ["start_order", "order_stats", "invoice", "abandoned_cart", "partners", "daily_report"]
}

variable "dlq_names" {
  description = "Colas de errores (sale del módulo serverless)."
  type        = map(string)
}

variable "partners_api_name" {
  description = "Nombre de la API de partners (sale del módulo serverless)."
  type        = string
}

variable "partners_api_stage" {
  description = "Stage de la API de partners."
  type        = string
}

variable "distribution_id" {
  description = "Distribución de CloudFront (sale del módulo edge). Sus métricas están en us-east-1."
  type        = string
}

variable "web_acl_name" {
  description = "WAF de CloudFront (null si está apagado)."
  type        = string
  default     = null
}

variable "api_5xx_threshold" {
  description = "Respuestas 5xx de la API en 5 minutos que disparan la alarma."
  type        = number
  default     = 5
}

variable "api_unhealthy_minutes" {
  description = "Minutos seguidos sin ninguna tarea sana antes de avisar (el primer apply tarda unos minutos en subir la imagen)."
  type        = number
  default     = 10
}

variable "rds_cpu_threshold" {
  description = "Porcentaje de CPU de RDS que dispara la alarma si se mantiene 15 minutos."
  type        = number
  default     = 80
}

variable "rds_free_storage_threshold_gb" {
  description = "GB libres en el disco de RDS por debajo de los que se avisa."
  type        = number
  default     = 2
}

variable "payments_declined_threshold" {
  description = "Pagos rechazados en una hora que disparan la alarma."
  type        = number
  default     = 5
}
