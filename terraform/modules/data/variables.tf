variable "name" {
  description = "Prefijo de nombres de los recursos (p. ej. infra-cloud-aws-dev)."
  type        = string
}

variable "vpc_id" {
  description = "VPC donde van la base de datos y la caché."
  type        = string
}

variable "data_subnet_ids" {
  description = "Subredes de datos (RDS y ElastiCache), una por AZ."
  type        = list(string)
}

variable "app_subnet_ids" {
  description = "Subredes de aplicación (para la instancia de pruebas)."
  type        = list(string)
}

variable "data_kms_key_arn" {
  description = "Clave KMS que cifra los datos: RDS, su secreto, DynamoDB, ElastiCache y S3 (sale del módulo security)."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "Clave KMS que cifra los logs de PostgreSQL en CloudWatch (sale del módulo security)."
  type        = string
}

variable "db_name" {
  description = "Nombre de la base de datos que se crea dentro de PostgreSQL."
  type        = string
  default     = "shopflow"
}

variable "db_username" {
  description = "Usuario administrador de PostgreSQL. La contraseña la genera y guarda RDS en Secrets Manager."
  type        = string
  default     = "shopflow_admin"
}

variable "db_engine_version" {
  description = "Versión mayor de PostgreSQL. RDS elige la última menor."
  type        = string
  default     = "17"
}

variable "db_instance_class" {
  description = "Tamaño de la instancia de RDS."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Disco de RDS en GB."
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Réplica en espera en otra AZ (dobla el coste; para prod)."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "Días de copias automáticas de RDS (0-35). Con más de 0 hay recuperación a un momento dado (PITR)."
  type        = number
  default     = 1

  validation {
    condition     = var.db_backup_retention_days >= 0 && var.db_backup_retention_days <= 35
    error_message = "db_backup_retention_days debe estar entre 0 y 35."
  }
}

variable "db_log_retention_days" {
  description = "Días que se guardan los logs de PostgreSQL en CloudWatch."
  type        = number
  default     = 7
}

variable "enable_cache" {
  description = "Crear ElastiCache Valkey (false para ahorrar mientras no se usa)."
  type        = bool
  default     = true
}

variable "cache_node_type" {
  description = "Tamaño del nodo de ElastiCache."
  type        = string
  default     = "cache.t4g.micro"
}

variable "cache_engine_version" {
  description = "Versión de Valkey."
  type        = string
  default     = "8.0"
}

variable "enable_test_client" {
  description = "Crear una instancia pequeña en la subred de aplicación para probar RDS y Valkey por SSM (necesita salida a Internet: nat_mode distinto de none)."
  type        = bool
  default     = false
}

variable "test_client_instance_type" {
  description = "Tipo de la instancia de pruebas (ARM/Graviton)."
  type        = string
  default     = "t4g.nano"
}

variable "cart_ttl_attribute" {
  description = "Atributo de la tabla de carritos con la fecha (epoch en segundos) en la que DynamoDB lo borra solo."
  type        = string
  default     = "expires_at"
}

variable "uploads_retention_days" {
  description = "Días que se guardan los ficheros del bucket de subidas."
  type        = number
  default     = 7
}

variable "force_destroy" {
  description = "Permite borrar buckets con ficheros, RDS sin snapshot final y la tabla sin protección (true en dev, para destroy por sesión)."
  type        = bool
  default     = true
}
