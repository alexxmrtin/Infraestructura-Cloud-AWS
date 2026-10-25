# VPC con 3 capas de subredes repartidas en var.az_count zonas:
#
#   public  10.0.0.0/24, 10.0.1.0/24 …   ALB y NAT. Ruta a Internet por el IGW.
#   app     10.0.10.0/24, 10.0.11.0/24 … ECS/EC2 y Lambdas. Salen a Internet por el NAT.
#   data    10.0.20.0/24, 10.0.21.0/24 … RDS y ElastiCache. Sin salida a Internet.


# Un "data" no crea nada, solo consulta. Aqui po ejemplo se consultan AZs , en que region estamos y el id de cuenta
data "aws_availability_zones" "available" {
  # checkov:skip=CKV_AWS_394:Se usan solo las primeras var.az_count zonas (slice); una AZ nueva no cambia la red.
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}


# Los locals son calculos que se hacen una vez y se reutilizan en todo el modulo "network"
locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count) #Cogemos las 2 primeras AZs

  # Desplazamiento del tercer octeto de cada capa (con un /16: 10.0.<offset + i>.0/24).
  tiers = {
    public = 0
    app    = 10
    data   = 20
  }

  # Lista de las 6 subredes (3 capas × 2 zonas), cada una con su capa, su zona y su rango.

  # Resultado:
  #   public-0 = { tier = "public", az = "eu-west-1a", cidr = "10.0.0.0/24" }
  #   public-1 = { tier = "public", az = "eu-west-1b", cidr = "10.0.1.0/24" }
  #   app-0    = { tier = "app",    az = "eu-west-1a", cidr = "10.0.10.0/24" }
  #   app-1    = { tier = "app",    az = "eu-west-1b", cidr = "10.0.11.0/24" }
  #   data-0   = { tier = "data",   az = "eu-west-1a", cidr = "10.0.20.0/24" }
  #   data-1   = { tier = "data",   az = "eu-west-1b", cidr = "10.0.21.0/24" }
  subnets = merge([
    for tier, offset in local.tiers : {
      for i, az in local.azs : "${tier}-${i}" => {
        tier = tier
        az   = az
        cidr = cidrsubnet(var.vpc_cidr, 8, offset + i)
      }
    }
  ]...)

  public_subnet_ids = [for i in range(var.az_count) : aws_subnet.this["public-${i}"].id]
  app_subnet_ids    = [for i in range(var.az_count) : aws_subnet.this["app-${i}"].id]
  data_subnet_ids   = [for i in range(var.az_count) : aws_subnet.this["data-${i}"].id]

  app_cidrs  = [for i in range(var.az_count) : local.subnets["app-${i}"].cidr]
  data_cidrs = [for i in range(var.az_count) : local.subnets["data-${i}"].cidr]
}

# Creacion de la VPC
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # necesario para los endpoints y para RDS por nombre

  tags = { Name = "${var.name}-vpc" }
}

#Creacion del internet gateway
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-igw" }
}

# Creacion de las subredes
resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  # Ni siquiera las públicas reparten IP pública: solo la tiene quien la pide (NAT, ALB).
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name}-${each.value.tier}-${substr(each.value.az, -1, 1)}"
    Tier = each.value.tier
  }
}

# El security group por defecto de la VPC se deja sin reglas: nadie debe usarlo.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-default-no-usar" }
}
