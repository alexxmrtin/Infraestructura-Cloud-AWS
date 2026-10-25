#DynamoDB es una base de datos de AWS sin servidor de tipo "clave -> valor": con una clave (aqui el ID del usuario) se guarda y se lee un dato al momento, sin tablas relacionadas como en RDS. Es muy rapida, escala sola y se paga por uso.

#En ShopFlow la usamos para el carrito de la compra: cada usuario tiene su carrito, que caduca solo si lo abandona. 
#Creamos el recurso de dynamoDB y crea una sola tabla que sera el carrito

resource "aws_dynamodb_table" "carts" {
  name         = "${var.name}-carts"
  billing_mode = "PAY_PER_REQUEST" #Se paga por cada lectura o escritura, no por capacidad reservada
  hash_key     = "user_id"         #La clave de cada carrito: el ID del usuario (el numero de la taquilla)

  #Solo se declara el campo de la clave. El resto (productos, cantidades...) DynamoDB lo acepta sin declararlo
  attribute {
    name = "user_id"
    type = "S" #S = texto
  }

  #Caducidad: cuando pasa la fecha del campo expires_at, DynamoDB borra el carrito solo
  ttl {
    attribute_name = var.cart_ttl_attribute
    enabled        = true
  }

  #Cuaderno de cambios: apunta como era el carrito antes de borrarse. Lo leera una Lambda en la fase 6 (carritos abandonados)
  stream_enabled   = true
  stream_view_type = "OLD_IMAGE"

  #Maquina del tiempo: se puede volver la tabla a cualquier momento de los ultimos 35 dias
  point_in_time_recovery {
    enabled = true
  }

  #Todo se guarda cifrado con la llave data de la fase 2
  server_side_encryption {
    enabled     = true
    kms_key_arn = var.data_kms_key_arn
  }

  #Seguro contra borrados. En dev force_destroy es true, asi que queda apagado y el destroy puede borrar la tabla
  deletion_protection_enabled = !var.force_destroy

  tags = { Name = "${var.name}-carts" }
}
