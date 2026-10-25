# Tablas de rutas: una para las públicas, una por AZ para las de aplicación (cada AZ puede tener su propio NAT Gateway) y una para las de datos.


# aws_route_table: la tabla de rutas en si
# aws_route: la ruta que se coloca en la tabla para que los recursos sepan donde ir
# aws_route_table_association: la subred a la que se asocia


# Tabla de rutas para public
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-rt-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = var.az_count

  subnet_id      = local.public_subnet_ids[count.index]
  route_table_id = aws_route_table.public.id
}


# Tabla de rutas para app
resource "aws_route_table" "app" {
  count = var.az_count

  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-rt-app-${substr(local.azs[count.index], -1, 1)}" }
}

resource "aws_route" "app_nat_gateway" {
  count = var.nat_mode == "gateway" ? var.az_count : 0

  route_table_id         = aws_route_table.app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.nat_gateway_per_az ? count.index : 0].id
}

resource "aws_route" "app_nat_instance" {
  count = var.nat_mode == "instance" ? var.az_count : 0

  route_table_id         = aws_route_table.app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat[0].primary_network_interface_id
}

resource "aws_route_table_association" "app" {
  count = var.az_count

  subnet_id      = local.app_subnet_ids[count.index]
  route_table_id = aws_route_table.app[count.index].id
}


#Tabla de rutas para data
# Datos: solo la ruta local de la VPC. Nunca Internet.
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-rt-data" }
}

resource "aws_route_table_association" "data" {
  count = var.az_count

  subnet_id      = local.data_subnet_ids[count.index]
  route_table_id = aws_route_table.data.id
}
