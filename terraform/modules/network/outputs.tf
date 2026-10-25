# Lo que el módulo de red entrega al terminar: la "tarjeta de datos" del edificio.Las fases siguientes (servidores, base de datos...) leen aquí dónde colocarse (module.network.app_subnet_ids, etc.) en vez de copiar IDs a mano.

# La VPC: vpc_id, vpc_cidr, azs
# Las subredes: public/app/data_subnet_ids (una subred por zona)
# Rangos de IPs: app/data_subnet_cidrs, para reglas de security groups
# Otras cosas: tablas de rutas de app, modo y ID del NAT, endpoint de S3,bucket de Flow Logs

output "vpc_id" {
  description = "ID de la VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "Rango de IPs de la VPC."
  value       = aws_vpc.this.cidr_block
}

output "azs" {
  description = "Zonas de disponibilidad usadas, en orden."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Subredes públicas (ALB, NAT), una por AZ."
  value       = local.public_subnet_ids
}

output "app_subnet_ids" {
  description = "Subredes privadas de aplicación (ECS, Lambdas), una por AZ."
  value       = local.app_subnet_ids
}

output "data_subnet_ids" {
  description = "Subredes privadas de datos (RDS, ElastiCache), una por AZ."
  value       = local.data_subnet_ids
}

output "app_subnet_cidrs" {
  description = "Rangos de las subredes de aplicación (para reglas de security groups)."
  value       = local.app_cidrs
}

output "data_subnet_cidrs" {
  description = "Rangos de las subredes de datos."
  value       = local.data_cidrs
}

output "app_route_table_ids" {
  description = "Tablas de rutas de aplicación (por si hacen falta más endpoints)."
  value       = aws_route_table.app[*].id
}

output "nat_mode" {
  description = "Modo de salida a Internet en uso."
  value       = var.nat_mode
}

output "nat_instance_id" {
  description = "ID de la instancia NAT (null si no se usa). Para entrar: aws ssm start-session --target <id>."
  value       = try(aws_instance.nat[0].id, null)
}

output "s3_endpoint_prefix_list_id" {
  description = "Prefix list del endpoint de S3, para reglas de salida de security groups."
  value       = aws_vpc_endpoint.gateway["s3"].prefix_list_id
}

output "flow_logs_bucket" {
  description = "Bucket donde se guardan los Flow Logs."
  value       = aws_s3_bucket.flow_logs.bucket
}
