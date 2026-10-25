# NACLs: un filtro grueso por capa, sin estado (hay que permitir ida y vuelta).
# El filtro fino lo hacen los security groups de cada servicio (fases 3 y 4).
#
#   public : web (80/443) y respuestas desde Internet; todo lo que venga de la VPC.
#   app    : todo lo que venga de la VPC y respuestas desde Internet (vía NAT).
#   data   : solo desde las subredes de aplicación (PostgreSQL y Valkey) y de datos.
#            La capa pública no puede hablar con la de datos.

# Como vimios en main.tf,locals son variables y calculos que se reutilizan en el modulo
locals {
  ephemeral = { from = 1024, to = 65535 }

  # Puertos de la capa de datos: PostgreSQL y Valkey/Redis.
  data_ports = { postgres = 5432, valkey = 6379 }

  # Reglas de cada subred (public,app y data)
  nacl_rules = {
    public = {
      ingress = {
        https     = { rule = 100, protocol = "tcp", cidr = "0.0.0.0/0", from = 443, to = 443 }
        http      = { rule = 110, protocol = "tcp", cidr = "0.0.0.0/0", from = 80, to = 80 }
        ephemeral = { rule = 120, protocol = "tcp", cidr = "0.0.0.0/0", from = local.ephemeral.from, to = local.ephemeral.to }
        vpc       = { rule = 130, protocol = "-1", cidr = var.vpc_cidr, from = 0, to = 0 }
      }
      egress = {
        all = { rule = 100, protocol = "-1", cidr = "0.0.0.0/0", from = 0, to = 0 }
      }
    }

    app = {
      ingress = {
        vpc       = { rule = 100, protocol = "-1", cidr = var.vpc_cidr, from = 0, to = 0 }
        ephemeral = { rule = 110, protocol = "tcp", cidr = "0.0.0.0/0", from = local.ephemeral.from, to = local.ephemeral.to }
      }
      egress = {
        all = { rule = 100, protocol = "-1", cidr = "0.0.0.0/0", from = 0, to = 0 }
      }
    }

    data = {
      ingress = merge(
        merge([
          for i, cidr in local.app_cidrs : {
            for j, name in keys(local.data_ports) : "${name}-app-${i}" => {
              rule = 100 + i * 10 + j, protocol = "tcp", cidr = cidr
              from = local.data_ports[name], to = local.data_ports[name]
            }
          }
        ]...),
        {
          for i, cidr in local.data_cidrs : "data-${i}" => {
            rule = 200 + i, protocol = "-1", cidr = cidr, from = 0, to = 0
          }
        },
      )
      egress = merge(
        {
          for i, cidr in local.app_cidrs : "app-${i}" => {
            rule = 100 + i, protocol = "tcp", cidr = cidr, from = 0, to = 65535
          }
        },
        {
          for i, cidr in local.data_cidrs : "data-${i}" => {
            rule = 200 + i, protocol = "-1", cidr = cidr, from = 0, to = 0
          }
        },
      )
    }
  }

  nacl_subnet_ids = {
    public = local.public_subnet_ids
    app    = local.app_subnet_ids
    data   = local.data_subnet_ids
  }

  nacl_rules_flat = merge([
    for tier, dirs in local.nacl_rules : merge([
      for dir, rules in dirs : {
        for key, r in rules : "${tier}-${dir}-${key}" => merge(r, { tier = tier, egress = dir == "egress" })
      }
    ]...)
  ]...)
}


#Definimos que ACL va con que subred
resource "aws_network_acl" "this" {
  # checkov:skip=CKV2_AWS_1:Las subredes se asocian con subnet_ids (checkov no lo ve por el for_each).
  for_each = local.nacl_subnet_ids

  vpc_id     = aws_vpc.this.id
  subnet_ids = each.value

  tags = { Name = "${var.name}-nacl-${each.key}" }
}

# Creamos las reglas dentro de la ACL para cada subred
resource "aws_network_acl_rule" "this" {
  for_each = local.nacl_rules_flat

  # checkov:skip=CKV_AWS_231:El rango efímero (1024-65535) incluye 3389, pero solo admite respuestas; los security groups cierran el resto.
  network_acl_id = aws_network_acl.this[each.value.tier].id
  rule_number    = each.value.rule
  egress         = each.value.egress
  protocol       = each.value.protocol
  rule_action    = "allow"
  cidr_block     = each.value.cidr
  from_port      = each.value.from
  to_port        = each.value.to
}
