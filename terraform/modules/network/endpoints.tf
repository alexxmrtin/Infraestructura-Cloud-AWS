# Gateway endpoints de S3 y DynamoDB: gratis y el tráfico no pasa por el NAT
# (que cobra por GB). Se enganchan a las tablas de aplicación; la capa de datos
# no los necesita (RDS y ElastiCache no salen de la VPC).

resource "aws_vpc_endpoint" "gateway" {
  for_each = toset(["s3", "dynamodb"]) #para cada una haz lo de abajo 1 vez

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.app[*].id

  tags = { Name = "${var.name}-vpce-${each.key}" }
}
