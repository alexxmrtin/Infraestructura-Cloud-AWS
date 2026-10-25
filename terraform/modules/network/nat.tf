# Salida a Internet de las subredes de aplicación, según var.nat_mode.

#Hay dos modos de NAT, el NAT gateway y el instance NAT. Se puede elegir uno u otro

# Un condicional que dependiendo del modo que se elija, selecciona un NAT u otro.
locals {
  nat_gateway_count = var.nat_mode == "gateway" ? (var.nat_gateway_per_az ? var.az_count : 1) : 0
}

resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = { Name = "${var.name}-nat-${count.index}" }

  depends_on = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------------------
# Opción "gateway": NAT Gateway gestionado (≈ 35 USD/mes cada uno + tráfico).
# ---------------------------------------------------------------------------

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = local.public_subnet_ids[count.index]

  tags = { Name = "${var.name}-natgw-${substr(local.azs[count.index], -1, 1)}" }

  depends_on = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------------------
# Opción "instance": una EC2 t4g.nano que hace de NAT (≈ 3 USD/mes + IP pública).
# Una sola instancia: si cae, las subredes privadas pierden Internet. Vale para dev.
# Sin SSH: se entra con SSM Session Manager.
# ---------------------------------------------------------------------------

#Preparamos politicas, roles y grupos de seguridad para la NAT instance (nota como cada bloque lleva un condicional para saber que NAT se ha elegido)

data "aws_ssm_parameter" "al2023_arm64" {
  count = var.nat_mode == "instance" ? 1 : 0

  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_security_group" "nat" {
  # checkov:skip=CKV2_AWS_5:Va enganchado a aws_instance.nat (checkov no lo ve por el count).
  count = var.nat_mode == "instance" ? 1 : 0

  name        = "${var.name}-nat-instance"
  description = "Instancia NAT: entra trafico de las subredes de aplicacion y sale a Internet"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name}-nat-instance" }
}

resource "aws_vpc_security_group_ingress_rule" "nat_from_app" {
  for_each = var.nat_mode == "instance" ? toset(local.app_cidrs) : toset([])

  security_group_id = aws_security_group.nat[0].id
  description       = "Todo el trafico desde la subred de aplicacion ${each.value}"
  ip_protocol       = "-1"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "nat_to_internet" {
  count = var.nat_mode == "instance" ? 1 : 0

  security_group_id = aws_security_group.nat[0].id
  description       = "Salida a Internet en nombre de las subredes privadas"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

data "aws_iam_policy_document" "nat_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "nat" {
  count = var.nat_mode == "instance" ? 1 : 0

  name               = "${var.name}-nat-instance"
  assume_role_policy = data.aws_iam_policy_document.nat_assume.json
}

resource "aws_iam_role_policy_attachment" "nat_ssm" {
  count = var.nat_mode == "instance" ? 1 : 0

  role       = aws_iam_role.nat[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nat" {
  count = var.nat_mode == "instance" ? 1 : 0

  name = "${var.name}-nat-instance"
  role = aws_iam_role.nat[0].name
}


#Creamos la instancia para el NAT instance
resource "aws_instance" "nat" {
  count = var.nat_mode == "instance" ? 1 : 0

  # checkov:skip=CKV_AWS_88:Una instancia NAT necesita IP pública para salir a Internet.
  # checkov:skip=CKV_AWS_126:Monitorización detallada innecesaria en dev (coste).
  ami                         = data.aws_ssm_parameter.al2023_arm64[0].insecure_value
  instance_type               = var.nat_instance_type
  subnet_id                   = local.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.nat[0].id]
  iam_instance_profile        = aws_iam_instance_profile.nat[0].name
  associate_public_ip_address = true
  source_dest_check           = false # imprescindible: reenvía paquetes que no son para ella
  ebs_optimized               = true
  user_data_replace_on_change = true

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    dnf install -y iptables-services
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/90-nat.conf
    sysctl -p /etc/sysctl.d/90-nat.conf
    IFACE=$(ip route show default | awk '{print $5; exit}')
    iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
    iptables -F FORWARD
    service iptables save
    systemctl enable --now iptables
  EOF

  metadata_options {
    http_tokens   = "required" # IMDSv2
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  tags = { Name = "${var.name}-nat-instance" }

  lifecycle {
    ignore_changes = [ami] # no recrear la NAT cada vez que sale una AMI nueva
  }

  # El user_data instala paquetes en el primer arranque: la subred pública
  # tiene que tener ya su ruta a Internet o la instancia se queda sin NAT.
  depends_on = [aws_route.public_internet, aws_route_table_association.public]
}
