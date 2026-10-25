locals {
  cloudfront_log_group_name = "/aws/cloudfront/${var.name}-shop"
  waf_log_group_name        = "aws-waf-logs-${var.name}-shop"
}

resource "aws_cloudwatch_log_group" "cloudfront" {
  # checkov:skip=CKV_AWS_158:CloudFront solo entrega logs en us-east-1 y las claves KMS del proyecto están en eu-west-1; CloudWatch los cifra con su clave.
  # checkov:skip=CKV_AWS_338:En dev los logs se guardan var.log_retention_days días (7), no un año, por coste.
  provider = aws.us_east_1

  name              = local.cloudfront_log_group_name
  retention_in_days = var.log_retention_days

  tags = { Name = "${var.name}-cloudfront" }
}

resource "aws_cloudwatch_log_group" "waf" {
  # checkov:skip=CKV_AWS_158:El WAF de CloudFront solo escribe en us-east-1 y las claves KMS del proyecto están en eu-west-1; CloudWatch los cifra con su clave.
  # checkov:skip=CKV_AWS_338:En dev los logs se guardan var.log_retention_days días (7), no un año, por coste.
  provider = aws.us_east_1
  count    = var.enable_waf ? 1 : 0

  name              = local.waf_log_group_name
  retention_in_days = var.log_retention_days

  tags = { Name = "${var.name}-waf" }
}

data "aws_iam_policy_document" "log_delivery" {
  statement {
    sid     = "AWSLogDeliveryWrite"
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = concat(
      ["${aws_cloudwatch_log_group.cloudfront.arn}:log-stream:*"],
      [for g in aws_cloudwatch_log_group.waf : "${g.arn}:log-stream:*"],
    )

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:us-east-1:${local.account_id}:*"]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "log_delivery" {
  provider = aws.us_east_1

  policy_name     = "${var.name}-log-delivery"
  policy_document = data.aws_iam_policy_document.log_delivery.json
}

resource "aws_cloudwatch_log_delivery_source" "cloudfront" {
  provider = aws.us_east_1

  name         = "${var.name}-cloudfront"
  log_type     = "ACCESS_LOGS"
  resource_arn = aws_cloudfront_distribution.shop.arn
}

resource "aws_cloudwatch_log_delivery_destination" "cloudfront" {
  provider = aws.us_east_1

  name          = "${var.name}-cloudfront"
  output_format = "json"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.cloudfront.arn
  }
}

resource "aws_cloudwatch_log_delivery" "cloudfront" {
  provider = aws.us_east_1

  delivery_source_name     = aws_cloudwatch_log_delivery_source.cloudfront.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.cloudfront.arn

  depends_on = [aws_cloudwatch_log_resource_policy.log_delivery]
}

resource "aws_wafv2_web_acl_logging_configuration" "shop" {
  provider = aws.us_east_1
  count    = var.enable_waf ? 1 : 0

  resource_arn            = aws_wafv2_web_acl.shop[0].arn
  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  logging_filter {
    default_behavior = "DROP"

    filter {
      behavior    = "KEEP"
      requirement = "MEETS_ANY"

      condition {
        action_condition {
          action = "BLOCK"
        }
      }

      condition {
        action_condition {
          action = "COUNT"
        }
      }
    }
  }

  depends_on = [aws_cloudwatch_log_resource_policy.log_delivery]
}

resource "aws_cloudwatch_query_definition" "cloudfront_errors" {
  provider = aws.us_east_1

  name            = "${var.name}/CloudFront - peticiones con error"
  log_group_names = [aws_cloudwatch_log_group.cloudfront.name]
  query_string    = <<-EOT
    fields @timestamp, `c-ip`, `cs-method`, `cs-uri-stem`, `sc-status`, `x-edge-result-type`, `time-taken`
    | filter `sc-status` >= 400
    | sort @timestamp desc
    | limit 50
  EOT
}

resource "aws_cloudwatch_query_definition" "cloudfront_top_paths" {
  provider = aws.us_east_1

  name            = "${var.name}/CloudFront - rutas mas pedidas"
  log_group_names = [aws_cloudwatch_log_group.cloudfront.name]
  query_string    = <<-EOT
    stats count(*) as peticiones, avg(`time-taken`) as segundos by `cs-uri-stem`
    | sort peticiones desc
    | limit 20
  EOT
}

resource "aws_cloudwatch_query_definition" "waf_blocked" {
  provider = aws.us_east_1
  count    = var.enable_waf ? 1 : 0

  name            = "${var.name}/WAF - peticiones bloqueadas"
  log_group_names = [aws_cloudwatch_log_group.waf[0].name]
  query_string    = <<-EOT
    fields @timestamp, httpRequest.clientIp, httpRequest.country, httpRequest.httpMethod, httpRequest.uri, terminatingRuleId
    | filter action = "BLOCK"
    | sort @timestamp desc
    | limit 50
  EOT
}
