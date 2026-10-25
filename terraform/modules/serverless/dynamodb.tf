# En este proyecto usamos dynamodb, que es una base de datos no relacional para almacenar datos que queremos que sea accesibles rapidamente y ademas escalables . En nuestro caso almacenaremos los pedidos y el carrito de cada usuario , ademas de el Stock de cada producto.

#Por tanto este archivo crea las tres tablas, cada bloque crea una tabla.


resource "aws_dynamodb_table" "orders" {
  name         = "${var.name}-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  global_secondary_index {
    name            = "by_user"
    projection_type = "ALL"

    key_schema {
      attribute_name = "user_id"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "created_at"
      key_type       = "RANGE"
    }
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.data_kms_key_arn
  }

  deletion_protection_enabled = !var.force_destroy

  tags = { Name = "${var.name}-orders" }
}

resource "aws_dynamodb_table" "stock" {
  name         = "${var.name}-stock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "product_id"

  attribute {
    name = "product_id"
    type = "N"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.data_kms_key_arn
  }

  deletion_protection_enabled = !var.force_destroy

  tags = { Name = "${var.name}-stock" }
}

resource "aws_dynamodb_table_item" "stock" {
  for_each = toset([for id in var.seed_product_ids : tostring(id)])

  table_name = aws_dynamodb_table.stock.name
  hash_key   = aws_dynamodb_table.stock.hash_key

  item = jsonencode({
    product_id = { N = each.key }
    stock      = { N = tostring(var.initial_stock) }
  })

  lifecycle {
    ignore_changes = [item]
  }
}

resource "aws_dynamodb_table" "stats" {
  name         = "${var.name}-order-stats"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.data_kms_key_arn
  }

  deletion_protection_enabled = !var.force_destroy

  tags = { Name = "${var.name}-order-stats" }
}
