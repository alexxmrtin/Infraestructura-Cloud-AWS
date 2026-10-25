# Elastic cache es un servicio gestionado por aws que usa una version open soruce de REDIS. Es una instancia que vive en tu red y se pone delante de las bases de datos o paginas web para mejorar el rendimiento guardando datos de manera temporal en cache.

#Si el parametro enable.cache esta en true se crean tres bloques, "aws_elasticache_subnet_group","aws_elasticache_parameter_group","aws_elasticache_replication_group"

#subnet_group: en que subredes vive la cache (las de datos, sin Internet)
#parameter_group: los ajustes de Valkey; cuando se llena, borra lo que menos se usa (allkeys-lru) (Valkey es el motor ue usa elasticache, es de redis)
#replication_group: la cache en si: un nodo t4g.micro, cifrado, y solo admite la pulsera data-clients

locals {
  cache_major_version = split(".", var.cache_engine_version)[0]
}

resource "aws_elasticache_subnet_group" "this" {
  count = var.enable_cache ? 1 : 0

  name       = "${var.name}-data"
  subnet_ids = var.data_subnet_ids

  tags = { Name = "${var.name}-data" }
}

resource "aws_elasticache_parameter_group" "this" {
  count = var.enable_cache ? 1 : 0

  name   = "${var.name}-valkey${local.cache_major_version}"
  family = "valkey${local.cache_major_version}"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  tags = { Name = "${var.name}-valkey" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_elasticache_replication_group" "this" {
  # checkov:skip=CKV2_AWS_50:Un solo nodo en dev (coste); sin réplica no hay failover automático.
  # checkov:skip=CKV_AWS_31:Sin AUTH: la caché solo guarda copias del catálogo y la protegen el security group, la subred sin Internet y TLS.
  count = var.enable_cache ? 1 : 0

  replication_group_id = "${var.name}-cache"
  description          = "${var.name}: cache del catalogo"

  engine               = "valkey"
  engine_version       = var.cache_engine_version
  node_type            = var.cache_node_type
  num_cache_clusters   = 1
  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.this[0].name

  subnet_group_name  = aws_elasticache_subnet_group.this[0].name
  security_group_ids = [aws_security_group.cache[0].id]

  at_rest_encryption_enabled = true
  kms_key_id                 = var.data_kms_key_arn
  transit_encryption_enabled = true

  automatic_failover_enabled = false
  multi_az_enabled           = false

  snapshot_retention_limit   = 1
  snapshot_window            = "02:00-03:00"
  maintenance_window         = "sun:03:30-sun:04:30"
  auto_minor_version_upgrade = true
  apply_immediately          = true

  tags = { Name = "${var.name}-cache" }
}
