# Aqui se crean en AWS Lambda las funciones de app/lambdas: Terraform hace un zip de cada carpeta y lo sube como una funcion.
# Las lanzan las colas de messaging.tf y el stream de carritos (bloques del final de este archivo), Step Functions, API Gateway y el Scheduler.

# Las ocho Lambdas:
# start_order: coge cada pedido de la cola orders-workflow y arranca su Step Functions.
# order_stats: coge cada pedido de la cola orders-stats y lo suma al total del dia.
# stock: reserva el stock de un pedido o lo devuelve si el pedido falla (la llama Step Functions).
# payment: cobro simulado, rechaza los pedidos de mas de 200 EUR (la llama Step Functions).
# invoice: genera la factura en PDF y la guarda en el bucket invoices (la llama Step Functions).
# abandoned_cart: avisa por email cuando un carrito caduca sin convertirse en pedido.
# partners: la API de los proveedores para consultar y cambiar el stock (la llama API Gateway).
# daily_report: manda por email el resumen de pedidos del dia anterior (la lanza el Scheduler a las 08:00).


# Lista de las ocho Lambdas con su descripcion, sus permisos (de iam.tf) y sus variables de entorno; abajo se saca el nombre real de cada una
locals {
  metrics_env = { METRICS_NAMESPACE = var.metrics_namespace, METRICS_ENVIRONMENT = var.name }

  lambdas = {
    start_order = {
      description = "Lee los pedidos de la cola y arranca su Step Functions"
      policy      = data.aws_iam_policy_document.start_order.json
      environment = { STATE_MACHINE_ARN = local.state_machine_arn }
    }
    order_stats = {
      description = "Suma cada pedido al total del dia"
      policy      = data.aws_iam_policy_document.order_stats.json
      environment = merge(local.metrics_env, { STATS_TABLE = aws_dynamodb_table.stats.name })
    }
    stock = {
      description = "Reserva o devuelve el stock de un pedido"
      policy      = data.aws_iam_policy_document.stock.json
      environment = merge(local.metrics_env, { STOCK_TABLE = aws_dynamodb_table.stock.name, ORDERS_TABLE = aws_dynamodb_table.orders.name })
    }
    payment = {
      description = "Cobro simulado"
      policy      = null
      environment = merge(local.metrics_env, { PAYMENT_LIMIT = tostring(var.payment_limit) })
    }
    invoice = {
      description = "Genera la factura en PDF y la guarda en S3"
      policy      = data.aws_iam_policy_document.invoice.json
      environment = { INVOICES_BUCKET = var.invoices_bucket_name }
    }
    abandoned_cart = {
      description = "Avisa cuando un carrito caduca sin pedido"
      policy      = data.aws_iam_policy_document.abandoned_cart.json
      environment = { NOTIFICATIONS_TOPIC_ARN = aws_sns_topic.notifications.arn }
    }
    partners = {
      description = "API de partners: consultar y cambiar el stock"
      policy      = data.aws_iam_policy_document.partners.json
      environment = { STOCK_TABLE = aws_dynamodb_table.stock.name }
    }
    daily_report = {
      description = "Manda el resumen de pedidos del dia anterior"
      policy      = data.aws_iam_policy_document.daily_report.json
      environment = { STATS_TABLE = aws_dynamodb_table.stats.name, NOTIFICATIONS_TOPIC_ARN = aws_sns_topic.notifications.arn }
    }
  }

  lambda_names = { for k in keys(local.lambdas) : k => "${var.name}-${replace(k, "_", "-")}" }
}

# Mete cada carpeta de app/lambdas en un zip, que es lo que acepta AWS Lambda
data "archive_file" "lambda" {
  for_each = local.lambdas

  type        = "zip"
  source_dir  = "${var.lambdas_dir}/${each.key}"
  output_path = "${path.root}/.terraform/lambdas/${each.key}.zip"
  excludes    = ["__pycache__"]
}

# Un log group por Lambda donde se guardan sus mensajes 7 dias, cifrados con la llave logs
resource "aws_cloudwatch_log_group" "lambda" {
  # checkov:skip=CKV_AWS_338:En dev los logs se guardan var.log_retention_days días (7), no un año, por coste.
  for_each = local.lambdas

  name              = "/aws/lambda/${local.lambda_names[each.key]}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = { Name = local.lambda_names[each.key] }
}

# Crea las ocho Lambdas: Python 3.13 en ARM, 128 MB, 10 segundos como maximo, con su zip, su rol y sus variables
resource "aws_lambda_function" "this" {
  # checkov:skip=CKV_AWS_117:Fuera de la VPC a propósito: solo usan APIs de AWS (DynamoDB, S3, SNS, Step Functions), no RDS ni Valkey.
  # checkov:skip=CKV_AWS_116:Los errores van a la DLQ de cada cola o del stream; las que llama Step Functions reintentan allí.
  # checkov:skip=CKV_AWS_115:Cuentas nuevas tienen 10 ejecuciones simultáneas en total; reservar concurrencia no deja crear las funciones.
  # checkov:skip=CKV_AWS_272:Sin firma de código en dev; el código sale del repo y lo sube el workflow.
  # checkov:skip=CKV_AWS_173:Las variables de entorno solo llevan nombres de tablas, temas y colas, nada secreto.
  for_each = local.lambdas

  function_name    = local.lambda_names[each.key]
  description      = each.value.description
  role             = aws_iam_role.lambda[each.key].arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "handler.handler"
  filename         = data.archive_file.lambda[each.key].output_path
  source_code_hash = data.archive_file.lambda[each.key].output_base64sha256
  memory_size      = 128
  timeout          = var.lambda_timeout

  environment {
    variables = each.value.environment
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.lambda[each.key].name
  }

  tracing_config {
    mode = "Active"
  }

  tags = { Name = local.lambda_names[each.key] }
}

# Conecta la cola orders-workflow con la Lambda start-order: cuando entra un pedido, la ejecuta
resource "aws_lambda_event_source_mapping" "start_order" {
  event_source_arn        = aws_sqs_queue.orders["workflow"].arn
  function_name           = aws_lambda_function.this["start_order"].arn
  batch_size              = 10
  function_response_types = ["ReportBatchItemFailures"]
}

# Conecta la cola orders-stats con la Lambda order-stats
resource "aws_lambda_event_source_mapping" "order_stats" {
  event_source_arn        = aws_sqs_queue.orders["stats"].arn
  function_name           = aws_lambda_function.this["order_stats"].arn
  batch_size              = 10
  function_response_types = ["ReportBatchItemFailures"]
}

# Conecta el stream de carritos con la Lambda abandoned-cart, solo para los carritos borrados por el TTL; si falla 3 veces va a su DLQ
resource "aws_lambda_event_source_mapping" "abandoned_cart" {
  event_source_arn                   = var.carts_stream_arn
  function_name                      = aws_lambda_function.this["abandoned_cart"].arn
  starting_position                  = "LATEST"
  batch_size                         = 10
  maximum_retry_attempts             = 3
  bisect_batch_on_function_error     = true
  function_response_types            = ["ReportBatchItemFailures"]
  maximum_batching_window_in_seconds = 0

  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["REMOVE"]
        userIdentity = {
          type        = ["Service"]
          principalId = ["dynamodb.amazonaws.com"]
        }
      })
    }
  }

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.abandoned_carts_dlq.arn
    }
  }
}
