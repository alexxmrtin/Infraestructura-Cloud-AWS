# Aqui se configuran los security groups para los diferentes servicios del modulo. Hay tres security groups, clients (quien puede hablr con cada servicio),rds (para la instancia que ejecuta la base de datos) y cache (para la instancia que ejecuta Valkey)

resource "aws_security_group" "clients" {
  # checkov:skip=CKV2_AWS_5:Se engancha a quien necesite la base de datos: la instancia de pruebas ahora, ECS y Lambdas en las fases 4 y 6.
  name        = "${var.name}-data-clients"
  description = "Quien lleve este grupo puede hablar con RDS y Valkey"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-data-clients" }
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds"
  description = "RDS PostgreSQL: solo admite el grupo data-clients"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-rds" }
}

resource "aws_security_group" "cache" {
  # checkov:skip=CKV2_AWS_5:Va enganchado a la caché (checkov no lo ve por el count).
  count = var.enable_cache ? 1 : 0

  name        = "${var.name}-cache"
  description = "ElastiCache Valkey: solo admite el grupo data-clients"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-cache" }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_clients" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL desde data-clients"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.clients.id
}

resource "aws_vpc_security_group_egress_rule" "clients_to_rds" {
  security_group_id            = aws_security_group.clients.id
  description                  = "PostgreSQL hacia RDS"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.rds.id
}

resource "aws_vpc_security_group_ingress_rule" "cache_from_clients" {
  count = var.enable_cache ? 1 : 0

  security_group_id            = aws_security_group.cache[0].id
  description                  = "Valkey desde data-clients"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.clients.id
}

resource "aws_vpc_security_group_egress_rule" "clients_to_cache" {
  count = var.enable_cache ? 1 : 0

  security_group_id            = aws_security_group.clients.id
  description                  = "Valkey hacia ElastiCache"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.cache[0].id
}
