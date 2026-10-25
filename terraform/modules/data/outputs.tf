output "clients_security_group_id" {
  description = "Grupo que hay que poner a quien necesite RDS o Valkey (ECS, Lambdas)."
  value       = aws_security_group.clients.id
}

output "db_endpoint" {
  description = "Dirección de RDS PostgreSQL (host)."
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "Puerto de PostgreSQL."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Nombre de la base de datos."
  value       = aws_db_instance.this.db_name
}

output "db_master_secret_arn" {
  description = "Secreto de Secrets Manager con el usuario y la contraseña de RDS (lo crea y rota RDS)."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "db_instance_id" {
  description = "Nombre de la instancia de RDS (para sus métricas y alarmas)."
  value       = aws_db_instance.this.identifier
}

output "db_resource_id" {
  description = "ID interno de RDS, para permisos rds-db:connect (login con IAM)."
  value       = aws_db_instance.this.resource_id
}

output "cache_endpoint" {
  description = "Dirección de Valkey (null si enable_cache = false). Siempre con TLS."
  value       = try(aws_elasticache_replication_group.this[0].primary_endpoint_address, null)
}

output "cache_port" {
  description = "Puerto de Valkey."
  value       = 6379
}

output "carts_table_name" {
  description = "Tabla DynamoDB de carritos."
  value       = aws_dynamodb_table.carts.name
}

output "carts_table_arn" {
  description = "ARN de la tabla de carritos."
  value       = aws_dynamodb_table.carts.arn
}

output "carts_stream_arn" {
  description = "Stream de la tabla de carritos (para la Lambda de carritos abandonados, fase 6)."
  value       = aws_dynamodb_table.carts.stream_arn
}

output "bucket_names" {
  description = "Buckets de la tienda: images, uploads, invoices."
  value       = { for k, b in aws_s3_bucket.this : k => b.bucket }
}

output "bucket_arns" {
  description = "ARN de cada bucket de la tienda."
  value       = { for k, b in aws_s3_bucket.this : k => b.arn }
}

output "test_client_instance_id" {
  description = "Instancia de pruebas (null si está apagada). Para entrar: aws ssm start-session --target <id>."
  value       = try(aws_instance.test_client[0].id, null)
}
