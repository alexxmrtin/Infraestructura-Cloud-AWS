# RDS se encarga de guardar todos los datos de la logica de negocio de la pagina web. (El carrito de cada usuario como hemos visto es NoSQL con dynamo db, el resto es relacional con RDS)

locals {
  db_identifier = "${var.name}-postgres"
}

# Definimos en que subredes puede ejecutarse rds
resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-data"
  subnet_ids = var.data_subnet_ids

  tags = { Name = "${var.name}-data" }
}

# Son ajustes de Postgre SQL como aceptar conexiones solo cifradas y logs
resource "aws_db_parameter_group" "this" {
  name   = "${var.name}-postgres${var.db_engine_version}"
  family = "postgres${var.db_engine_version}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "500"
  }

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = { Name = "${var.name}-postgres" }

  lifecycle {
    create_before_destroy = true
  }
}

# Se crea la carpeta (enlace al recurso dentro del servicio de cloudwatch) donde vamos a guardar todos los logs referentes a rds que hemos configurado antes
resource "aws_cloudwatch_log_group" "rds" {
  # checkov:skip=CKV_AWS_338:En dev los logs se guardan var.db_log_retention_days días (7), no un año, por coste.
  name              = "/aws/rds/instance/${local.db_identifier}/postgresql"
  retention_in_days = var.db_log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = { Name = "${local.db_identifier}-logs" }
}

# Y por ultimo la instancia que aloja la base de datos
resource "aws_db_instance" "this" {
  # checkov:skip=CKV_AWS_157:Multi-AZ detrás de var.db_multi_az (dobla el coste; apagado en dev).
  # checkov:skip=CKV_AWS_293:Sin protección contra borrado en dev: el entorno se destruye en cada sesión.
  # checkov:skip=CKV_AWS_118:Sin Enhanced Monitoring (necesita otro rol y cuesta); bastan las métricas de CloudWatch y Performance Insights.
  identifier     = local.db_identifier
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_username

  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.data_kms_key_arn

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id        = var.data_kms_key_arn

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  iam_database_authentication_enabled = true

  backup_retention_period   = var.db_backup_retention_days
  backup_window             = "02:00-03:00"
  maintenance_window        = "sun:03:30-sun:04:30"
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = var.force_destroy
  final_snapshot_identifier = var.force_destroy ? null : "${local.db_identifier}-final"
  deletion_protection       = !var.force_destroy
  delete_automated_backups  = true

  auto_minor_version_upgrade = true
  apply_immediately          = true

  enabled_cloudwatch_logs_exports = ["postgresql"]

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.data_kms_key_arn
  performance_insights_retention_period = 7

  tags = { Name = local.db_identifier }

  depends_on = [aws_cloudwatch_log_group.rds]
}
