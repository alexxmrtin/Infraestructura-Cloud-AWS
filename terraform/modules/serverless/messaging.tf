# Cuando un usuario pulsa el boton de crear pedido se producen varias cosas simultaneamente (restar stock, cobrar, generar factura, mandar un mensaje al corre electronico). Para dividir el trabajo y aumentar la velocidad, estas tareas no las ejecuta la API, usamos SQS,SNS y DLQ para hacer que se puedan comunicar la API y los servicios que van a ejecutar esas tareas que son funciones lambda.

# SNS: reparte cada mensaje que recibe, una copia a cada suscriptor (colas, emails...). No guarda nada.
# SQS: cola que guarda los mensajes hasta que una Lambda los recoge. Si la Lambda falla, el mensaje vuelve a la cola y se reintenta.
# DLQ: cola aparte donde acaba un mensaje que ha fallado 3 veces, para revisarlo en vez de reintentarlo para siempre.

#---

# 1.La API escribe en orders: “pedido 3f2a…”.
# 2.SNS deja una copia en cada cola suscrita (orders-workflow y orders-stats). Esto se configura en el bloque aws_sns_topic_subscription "orders".
# 3.Cada cola tiene una Lambda asignada que la vigila. Cuando entra el mensaje, la cola despierta a su Lambda:
#       orders-workflow → Lambda start-order → arranca Step Functions.
#       orders-stats → Lambda order-stats → suma al total del día.
# 4.Step Functions llama directamente a las Lambdas stock, payment e invoice, una detrás de otra. Aquí ya no hay temas ni colas por medio.
# 5.Al final, Step Functions escribe en notifications: “pedido confirmado”, y SNS te lo manda por email.

#---



# Nombres de las dos colas del pedido: workflow (procesar el pedido) y stats (sumarlo al total del dia)
locals {
  order_queues = {
    workflow = "${var.name}-orders-workflow"
    stats    = "${var.name}-orders-stats"
  }
}


# Tema SNS donde la API publica cada pedido nuevo
resource "aws_sns_topic" "orders" {
  name              = "${var.name}-orders"
  kms_master_key_id = var.data_kms_key_arn

  tags = { Name = "${var.name}-orders" }
}

# Tema SNS de los avisos de la tienda (pedido confirmado o rechazado, carrito abandonado, resumen diario)
resource "aws_sns_topic" "notifications" {
  name              = "${var.name}-notifications"
  kms_master_key_id = var.data_kms_key_arn

  tags = { Name = "${var.name}-notifications" }
}

# Suscribe tu email al tema de avisos; si notification_email esta vacio no se crea
resource "aws_sns_topic_subscription" "email" {
  count = var.notification_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# Las dos DLQ, una por cola, donde acaban los mensajes que fallan 3 veces (se guardan 14 dias)
resource "aws_sqs_queue" "dlq" {
  for_each = local.order_queues

  name                      = "${each.value}-dlq"
  message_retention_seconds = 1209600
  kms_master_key_id         = var.data_kms_key_arn

  tags = { Name = "${each.value}-dlq" }
}

# Las dos colas del pedido; tras 3 fallos mandan el mensaje a su DLQ
resource "aws_sqs_queue" "orders" {
  for_each = local.order_queues

  name                       = each.value
  visibility_timeout_seconds = var.lambda_timeout * 6
  message_retention_seconds  = 345600
  kms_master_key_id          = var.data_kms_key_arn

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = var.queue_max_receive_count
  })

  tags = { Name = each.value }
}

# Permiso para que SNS escriba en las colas, solo si el mensaje viene del tema orders
data "aws_iam_policy_document" "orders_queue" {
  for_each = aws_sqs_queue.orders

  statement {
    sid       = "AllowOrdersTopic"
    actions   = ["sqs:SendMessage"]
    resources = [each.value.arn]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.orders.arn]
    }
  }
}

# Pega ese permiso a cada una de las dos colas
resource "aws_sqs_queue_policy" "orders" {
  for_each = aws_sqs_queue.orders

  queue_url = each.value.id
  policy    = data.aws_iam_policy_document.orders_queue[each.key].json
}

# Suscribe las dos colas al tema orders: cada pedido llega una vez a cada cola (fan-out)
resource "aws_sns_topic_subscription" "orders" {
  for_each = aws_sqs_queue.orders

  topic_arn            = aws_sns_topic.orders.arn
  protocol             = "sqs"
  endpoint             = each.value.arn
  raw_message_delivery = true

  depends_on = [aws_sqs_queue_policy.orders]
}

# DLQ de la Lambda de carritos abandonados, donde acaban los avisos que fallan 3 veces
resource "aws_sqs_queue" "abandoned_carts_dlq" {
  name                      = "${var.name}-abandoned-carts-dlq"
  message_retention_seconds = 1209600
  kms_master_key_id         = var.data_kms_key_arn

  tags = { Name = "${var.name}-abandoned-carts-dlq" }
}
