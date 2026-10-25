resource "aws_api_gateway_rest_api" "partners" {
  name        = "${var.name}-partners"
  description = "API de partners de ShopFlow: stock con API key y limites por partner"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = { Name = "${var.name}-partners" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_resource" "stock" {
  rest_api_id = aws_api_gateway_rest_api.partners.id
  parent_id   = aws_api_gateway_rest_api.partners.root_resource_id
  path_part   = "stock"
}

resource "aws_api_gateway_resource" "stock_item" {
  rest_api_id = aws_api_gateway_rest_api.partners.id
  parent_id   = aws_api_gateway_resource.stock.id
  path_part   = "{product_id}"
}

resource "aws_api_gateway_model" "stock" {
  rest_api_id  = aws_api_gateway_rest_api.partners.id
  name         = "Stock"
  content_type = "application/json"

  schema = jsonencode({
    "$schema"            = "http://json-schema.org/draft-04/schema#"
    type                 = "object"
    required             = ["stock"]
    additionalProperties = false
    properties = {
      stock = { type = "integer", minimum = 0, maximum = 100000 }
    }
  })
}

resource "aws_api_gateway_request_validator" "all" {
  rest_api_id                 = aws_api_gateway_rest_api.partners.id
  name                        = "body-and-params"
  validate_request_body       = true
  validate_request_parameters = true
}

resource "aws_api_gateway_method" "list_stock" {
  # checkov:skip=CKV2_AWS_53:GET sin cuerpo ni parámetros que validar.
  rest_api_id      = aws_api_gateway_rest_api.partners.id
  resource_id      = aws_api_gateway_resource.stock.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_method" "set_stock" {
  rest_api_id          = aws_api_gateway_rest_api.partners.id
  resource_id          = aws_api_gateway_resource.stock_item.id
  http_method          = "PUT"
  authorization        = "NONE"
  api_key_required     = true
  request_validator_id = aws_api_gateway_request_validator.all.id
  request_models       = { "application/json" = aws_api_gateway_model.stock.name }
  request_parameters   = { "method.request.path.product_id" = true }
}

resource "aws_api_gateway_integration" "list_stock" {
  rest_api_id             = aws_api_gateway_rest_api.partners.id
  resource_id             = aws_api_gateway_resource.stock.id
  http_method             = aws_api_gateway_method.list_stock.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.this["partners"].invoke_arn
}

resource "aws_api_gateway_integration" "set_stock" {
  rest_api_id             = aws_api_gateway_rest_api.partners.id
  resource_id             = aws_api_gateway_resource.stock_item.id
  http_method             = aws_api_gateway_method.set_stock.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.this["partners"].invoke_arn
}

resource "aws_lambda_permission" "partners" {
  statement_id  = "AllowPartnersApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this["partners"].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.partners.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "partners" {
  rest_api_id = aws_api_gateway_rest_api.partners.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.stock,
      aws_api_gateway_resource.stock_item,
      aws_api_gateway_model.stock,
      aws_api_gateway_method.list_stock,
      aws_api_gateway_method.set_stock,
      aws_api_gateway_integration.list_stock,
      aws_api_gateway_integration.set_stock,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "partners_api" {
  # checkov:skip=CKV_AWS_338:En dev los logs se guardan var.log_retention_days días (7), no un año, por coste.
  name              = "/aws/apigateway/${var.name}-partners"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = { Name = "${var.name}-partners" }
}

data "aws_iam_policy_document" "apigateway_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apigateway_logs" {
  name               = "${var.name}-apigateway-logs"
  assume_role_policy = data.aws_iam_policy_document.apigateway_assume.json
}

resource "aws_iam_role_policy_attachment" "apigateway_logs" {
  role       = aws_iam_role.apigateway_logs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.apigateway_logs.arn

  depends_on = [aws_iam_role_policy_attachment.apigateway_logs]
}

resource "aws_api_gateway_stage" "v1" {
  # checkov:skip=CKV2_AWS_29:Sin WAF en la API de partners: la protegen la API key, los límites del usage plan y la validación.
  # checkov:skip=CKV2_AWS_51:Sin certificado de cliente: la API llama a Lambda, no a un backend HTTP que tenga que comprobar el origen.
  # checkov:skip=CKV_AWS_120:Sin caché: el stock tiene que salir siempre actualizado y la caché de API Gateway se paga por hora.
  rest_api_id          = aws_api_gateway_rest_api.partners.id
  deployment_id        = aws_api_gateway_deployment.partners.id
  stage_name           = "v1"
  xray_tracing_enabled = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.partners_api.arn
    format = jsonencode({
      requestId = "$context.requestId"
      ip        = "$context.identity.sourceIp"
      apiKeyId  = "$context.identity.apiKeyId"
      method    = "$context.httpMethod"
      path      = "$context.resourcePath"
      status    = "$context.status"
      latencyMs = "$context.responseLatency"
      error     = "$context.error.message"
    })
  }

  tags = { Name = "${var.name}-partners-v1" }

  depends_on = [aws_api_gateway_account.this]
}

resource "aws_api_gateway_method_settings" "all" {
  # checkov:skip=CKV_AWS_225:Sin caché (ver el stage).
  rest_api_id = aws_api_gateway_rest_api.partners.id
  stage_name  = aws_api_gateway_stage.v1.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled        = true
    logging_level          = "ERROR"
    data_trace_enabled     = false
    throttling_rate_limit  = var.partners_rate_limit * 4
    throttling_burst_limit = var.partners_burst_limit * 4
  }
}

resource "aws_api_gateway_api_key" "partner" {
  name        = "${var.name}-partner-demo"
  description = "API key del partner de prueba"
}

resource "aws_api_gateway_usage_plan" "partners" {
  name = "${var.name}-partners"

  api_stages {
    api_id = aws_api_gateway_rest_api.partners.id
    stage  = aws_api_gateway_stage.v1.stage_name
  }

  throttle_settings {
    rate_limit  = var.partners_rate_limit
    burst_limit = var.partners_burst_limit
  }

  quota_settings {
    limit  = var.partners_daily_quota
    period = "DAY"
  }
}

resource "aws_api_gateway_usage_plan_key" "partner" {
  key_id        = aws_api_gateway_api_key.partner.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.partners.id
}
