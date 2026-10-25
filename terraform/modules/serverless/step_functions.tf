# Aqui se crea en Step Functions el flujo de cada pedido: reservar stock, cobrar, factura, marcarlo confirmado y avisar por email.
# Si algo falla, devuelve el stock, marca el pedido como fallido y avisa. Lo arranca la Lambda start_order con el order_id como nombre.


# Reintentos que se reutilizan en los pasos y la receta del pedido (los pasos de la maquina de estados)
locals {
  # Si falla AWS Lambda (no nuestro codigo), reintenta 3 veces esperando 2, 4 y 8 segundos
  lambda_retry = [
    {
      ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException", "Lambda.TooManyRequestsException"]
      IntervalSeconds = 2
      MaxAttempts     = 3
      BackoffRate     = 2
    }
  ]

  # Lo mismo para los pasos que hablan directo con DynamoDB o SNS
  service_retry = [
    {
      ErrorEquals     = ["States.TaskFailed"]
      IntervalSeconds = 2
      MaxAttempts     = 3
      BackoffRate     = 2
    }
  ]

  # La receta del pedido: empieza en ReserveStock y cada paso dice cual va despues
  order_workflow = {
    Comment = "Pedido de ShopFlow: reservar stock, cobrar, factura y aviso. Si algo falla, se devuelve el stock y se avisa."
    StartAt = "ReserveStock"
    States = {
      # Paso 1: llama a la Lambda stock para reservar las unidades; si falla, el pedido va a MarkFailed
      ReserveStock = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.this["stock"].arn
          Payload = {
            action       = "reserve"
            "order_id.$" = "$.order_id"
            "items.$"    = "$.items"
          }
        }
        ResultPath = null
        Retry      = local.lambda_retry
        Catch      = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.error", Next = "MarkFailed" }]
        Next       = "ProcessPayment"
      }

      # Paso 2: llama a la Lambda payment para cobrar y guarda el payment_id; si falla, devuelve el stock
      ProcessPayment = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.this["payment"].arn
          Payload = {
            "order_id.$" = "$.order_id"
            "total.$"    = "$.total"
          }
        }
        ResultSelector = { "payment_id.$" = "$.Payload.payment_id" }
        ResultPath     = "$.payment"
        Retry          = local.lambda_retry
        Catch          = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.error", Next = "ReleaseStock" }]
        Next           = "GenerateInvoice"
      }

      # Paso 3: llama a la Lambda invoice para hacer el PDF y guarda su ruta en S3; si falla, devuelve el stock
      GenerateInvoice = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.this["invoice"].arn
          "Payload.$"  = "$"
        }
        ResultSelector = { "key.$" = "$.Payload.key" }
        ResultPath     = "$.invoice"
        Retry          = local.lambda_retry
        Catch          = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.error", Next = "ReleaseStock" }]
        Next           = "MarkConfirmed"
      }

      # Paso 4: marca el pedido como CONFIRMED en la tabla orders, sin Lambda (Step Functions habla con DynamoDB)
      MarkConfirmed = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName                = aws_dynamodb_table.orders.name
          Key                      = { order_id = { "S.$" = "$.order_id" } }
          UpdateExpression         = "SET #status = :status, payment_id = :payment, invoice_key = :invoice, updated_at = :now"
          ExpressionAttributeNames = { "#status" = "status" }
          ExpressionAttributeValues = {
            ":status"  = { S = "CONFIRMED" }
            ":payment" = { "S.$" = "$.payment.payment_id" }
            ":invoice" = { "S.$" = "$.invoice.key" }
            ":now"     = { "S.$" = "$$.State.EnteredTime" }
          }
        }
        ResultPath = null
        Retry      = local.service_retry
        Next       = "NotifyConfirmed"
      }

      # Paso 5: manda el email de pedido confirmado por el tema notifications y termina bien
      NotifyConfirmed = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.notifications.arn
          Subject     = "ShopFlow: pedido confirmado"
          "Message.$" = "States.Format('Pedido {} confirmado. Cliente: {}. Total: {} EUR. Factura: s3://${var.invoices_bucket_name}/{}', $.order_id, $.email, $.total, $.invoice.key)"
        }
        ResultPath = null
        Retry      = local.service_retry
        End        = true
      }

      # Si falla el cobro o la factura: llama a la Lambda stock para devolver las unidades reservadas
      ReleaseStock = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.this["stock"].arn
          Payload = {
            action       = "release"
            "order_id.$" = "$.order_id"
            "items.$"    = "$.items"
          }
        }
        ResultPath = null
        Retry      = local.lambda_retry
        Catch      = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.release_error", Next = "MarkFailed" }]
        Next       = "MarkFailed"
      }

      # Marca el pedido como FAILED en la tabla orders con el motivo del fallo
      MarkFailed = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName                = aws_dynamodb_table.orders.name
          Key                      = { order_id = { "S.$" = "$.order_id" } }
          UpdateExpression         = "SET #status = :status, failure_reason = :reason, updated_at = :now"
          ExpressionAttributeNames = { "#status" = "status" }
          ExpressionAttributeValues = {
            ":status" = { S = "FAILED" }
            ":reason" = { "S.$" = "$.error.Error" }
            ":now"    = { "S.$" = "$$.State.EnteredTime" }
          }
        }
        ResultPath = null
        Retry      = local.service_retry
        Next       = "NotifyFailed"
      }

      # Manda el email de pedido rechazado por el tema notifications
      NotifyFailed = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.notifications.arn
          Subject     = "ShopFlow: pedido rechazado"
          "Message.$" = "States.Format('Pedido {} rechazado. Cliente: {}. Total: {} EUR. Motivo: {}', $.order_id, $.email, $.total, $.error.Error)"
        }
        ResultPath = null
        Retry      = local.service_retry
        Next       = "OrderFailed"
      }

      # Final en rojo: la ejecucion sale como fallida en la consola
      OrderFailed = {
        Type  = "Fail"
        Error = "OrderFailed"
        Cause = "El pedido no se ha podido completar; el stock se ha devuelto."
      }
    }
  }
}

# Grupo de logs donde Step Functions escribe cada paso de cada pedido
resource "aws_cloudwatch_log_group" "order_workflow" {
  # checkov:skip=CKV_AWS_338:En dev los logs se guardan var.log_retention_days días (7), no un año, por coste.
  name              = "/aws/vendedlogs/states/${local.state_machine_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = { Name = local.state_machine_name }
}

# Quien puede ponerse el rol: solo Step Functions de nuestra cuenta
data "aws_iam_policy_document" "states_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

# El rol que usa la maquina de estados
resource "aws_iam_role" "order_workflow" {
  name               = local.state_machine_name
  assume_role_policy = data.aws_iam_policy_document.states_assume.json
}

# Permisos del rol: llamar a las 3 Lambdas, escribir en orders, publicar en SNS, usar la llave data, logs y X-Ray
data "aws_iam_policy_document" "order_workflow" {
  # checkov:skip=CKV_AWS_111:La entrega de logs y X-Ray de Step Functions no admiten recursos concretos; es lo que pide AWS.
  # checkov:skip=CKV_AWS_356:Ídem.
  statement {
    sid     = "InvokeSteps"
    actions = ["lambda:InvokeFunction"]
    resources = flatten([
      for k in ["stock", "payment", "invoice"] : [aws_lambda_function.this[k].arn, "${aws_lambda_function.this[k].arn}:*"]
    ])
  }

  statement {
    sid       = "UpdateOrders"
    actions   = ["dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.orders.arn]
  }

  statement {
    sid       = "Notify"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.notifications.arn]
  }

  statement {
    sid       = "UseDataKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.data_kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["dynamodb.${local.region}.amazonaws.com", "sns.${local.region}.amazonaws.com"]
    }
  }

  statement {
    sid = "DeliverLogs"
    actions = [
      "logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery", "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "WriteTraces"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules", "xray:GetSamplingTargets"]
    resources = ["*"]
  }
}

# Pega esos permisos al rol
resource "aws_iam_role_policy" "order_workflow" {
  name   = "workflow"
  role   = aws_iam_role.order_workflow.id
  policy = data.aws_iam_policy_document.order_workflow.json
}

# La maquina de estados del pedido: une la receta, el rol, los logs y X-Ray
resource "aws_sfn_state_machine" "order" {
  name       = local.state_machine_name
  type       = "STANDARD"
  role_arn   = aws_iam_role.order_workflow.arn
  definition = jsonencode(local.order_workflow)

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.order_workflow.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tracing_configuration {
    enabled = true
  }

  tags = { Name = local.state_machine_name }

  depends_on = [aws_iam_role_policy.order_workflow]
}
