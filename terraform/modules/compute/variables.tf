variable "name" {
  description = "Prefijo de nombres de los recursos (p. ej. infra-cloud-aws-dev)."
  type        = string
}

variable "vpc_id" {
  description = "VPC donde van el ALB y las instancias."
  type        = string
}

variable "public_subnet_ids" {
  description = "Subredes públicas para el ALB (al menos dos AZ)."
  type        = list(string)
}

variable "app_subnet_ids" {
  description = "Subredes de aplicación para las instancias y las tareas de ECS."
  type        = list(string)
}

variable "data_clients_security_group_id" {
  description = "Grupo data-clients del módulo data: se lo ponemos a las tareas para que lleguen a RDS y Valkey."
  type        = string
}

variable "data_kms_key_arn" {
  description = "Clave KMS data: discos EBS, copias de AWS Backup y el secreto de RDS (sale del módulo security)."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "Clave KMS logs: logs de la API en CloudWatch (sale del módulo security)."
  type        = string
}

variable "db_host" {
  description = "Dirección de RDS PostgreSQL."
  type        = string
}

variable "db_port" {
  description = "Puerto de PostgreSQL."
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "Nombre de la base de datos."
  type        = string
}

variable "db_secret_arn" {
  description = "Secreto de Secrets Manager con el usuario y la contraseña de RDS."
  type        = string
}

variable "cache_host" {
  description = "Dirección de Valkey (null si la caché está apagada)."
  type        = string
  default     = null
}

variable "carts_table_name" {
  description = "Tabla DynamoDB de carritos."
  type        = string
}

variable "carts_table_arn" {
  description = "ARN de la tabla de carritos (para el permiso de la API)."
  type        = string
}

variable "orders_table_name" {
  description = "Tabla DynamoDB de pedidos (sale del módulo serverless)."
  type        = string
}

variable "orders_table_arn" {
  description = "ARN de la tabla de pedidos."
  type        = string
}

variable "stock_table_name" {
  description = "Tabla DynamoDB de stock (sale del módulo serverless)."
  type        = string
}

variable "stock_table_arn" {
  description = "ARN de la tabla de stock."
  type        = string
}

variable "orders_topic_arn" {
  description = "Tema SNS donde la API publica cada pedido nuevo (sale del módulo serverless)."
  type        = string
}

variable "invoices_bucket_name" {
  description = "Bucket de facturas, para darle al cliente un enlace temporal a la suya."
  type        = string
}

variable "invoices_bucket_arn" {
  description = "ARN del bucket de facturas."
  type        = string
}

variable "certificate_arn" {
  description = "Certificado de ACM del ALB (sale del módulo edge)."
  type        = string
}

variable "origin_verify_header" {
  description = "Cabecera secreta que pone CloudFront; sin ella el ALB contesta 403."
  type        = string
}

variable "origin_verify_value" {
  description = "Valor de la cabecera secreta (sale del módulo edge)."
  type        = string
  sensitive   = true
}

variable "cognito_user_pool_id" {
  description = "User pool de Cognito con el que la API comprueba los tokens."
  type        = string
}

variable "cognito_client_id" {
  description = "Cliente de la web en Cognito (los tokens deben ser suyos)."
  type        = string
}

variable "instance_type" {
  description = "Tipo de las instancias de ECS (ARM/Graviton)."
  type        = string
  default     = "t4g.small"
}

variable "root_volume_size" {
  description = "Disco EBS de cada instancia en GB (la AMI de ECS pide 30 como mínimo)."
  type        = number
  default     = 30
}

variable "asg_min_size" {
  description = "Instancias mínimas del Auto Scaling Group."
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Instancias máximas del Auto Scaling Group."
  type        = number
  default     = 3
}

variable "container_port" {
  description = "Puerto en el que escucha la API dentro del contenedor."
  type        = number
  default     = 8000
}

variable "api_image_tag" {
  description = "Etiqueta de la imagen de la API en ECR."
  type        = string
  default     = "latest"
}

variable "api_cpu" {
  description = "CPU de cada tarea (1024 = 1 vCPU)."
  type        = number
  default     = 256
}

variable "api_memory" {
  description = "Memoria de cada tarea en MiB."
  type        = number
  default     = 512
}

variable "api_desired_count" {
  description = "Tareas de la API al crear el servicio (luego manda el autoscaling)."
  type        = number
  default     = 2
}

variable "api_min_count" {
  description = "Tareas mínimas de la API."
  type        = number
  default     = 1
}

variable "api_max_count" {
  description = "Tareas máximas de la API."
  type        = number
  default     = 4
}

variable "api_cpu_target" {
  description = "Uso medio de CPU de las tareas (%) que el autoscaling intenta mantener."
  type        = number
  default     = 60
}

variable "api_requests_per_target" {
  description = "Peticiones por minuto a cada tarea que el autoscaling intenta mantener."
  type        = number
  default     = 120
}

variable "ecr_keep_images" {
  description = "Imágenes de la API que se guardan en ECR."
  type        = number
  default     = 5
}

variable "log_retention_days" {
  description = "Días que se guardan los logs de la API en CloudWatch."
  type        = number
  default     = 7
}

variable "enable_backup" {
  description = "Crear AWS Backup para los discos EBS de las instancias."
  type        = bool
  default     = true
}

variable "backup_schedule" {
  description = "Cuándo se hace la copia (expresión cron de AWS, hora UTC)."
  type        = string
  default     = "cron(0 3 * * ? *)"
}

variable "backup_retention_days" {
  description = "Días que se guarda cada copia de EBS."
  type        = number
  default     = 7
}

variable "force_destroy" {
  description = "Permite borrar ECR con imágenes, el servicio sin vaciarlo y el almacén de copias con copias dentro (true en dev)."
  type        = bool
  default     = true
}
