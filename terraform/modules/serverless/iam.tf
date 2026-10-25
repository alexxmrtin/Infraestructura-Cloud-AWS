data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "lambda" {
  for_each = local.lambdas

  name               = local.lambda_names[each.key]
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda" {
  # checkov:skip=CKV_AWS_356:X-Ray no admite recursos concretos en PutTraceSegments; tiene que ser "*".
  for_each = local.lambdas

  source_policy_documents = compact([each.value.policy])

  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda[each.key].arn}:*"]
  }

  statement {
    sid       = "WriteTraces"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  for_each = local.lambdas

  name   = "function"
  role   = aws_iam_role.lambda[each.key].id
  policy = data.aws_iam_policy_document.lambda[each.key].json
}

data "aws_iam_policy_document" "start_order" {
  statement {
    sid       = "StartOrderWorkflow"
    actions   = ["states:StartExecution"]
    resources = [local.state_machine_arn]
  }

  statement {
    sid       = "ReadQueue"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.orders["workflow"].arn]
  }

  statement {
    sid       = "DecryptQueue"
    actions   = ["kms:Decrypt"]
    resources = [var.data_kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["sqs.${local.region}.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "order_stats" {
  statement {
    sid       = "WriteStats"
    actions   = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.stats.arn]
  }

  statement {
    sid       = "ReadQueue"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.orders["stats"].arn]
  }

  statement {
    sid       = "UseDataKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.data_kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["sqs.${local.region}.amazonaws.com", "dynamodb.${local.region}.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "stock" {
  statement {
    sid       = "UpdateStockAndOrder"
    actions   = ["dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.stock.arn, aws_dynamodb_table.orders.arn]
  }

  statement {
    sid       = "UseDataKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.data_kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["dynamodb.${local.region}.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "invoice" {
  statement {
    sid       = "WriteInvoices"
    actions   = ["s3:PutObject"]
    resources = ["${var.invoices_bucket_arn}/*"]
  }

  statement {
    sid       = "UseDataKey"
    actions   = ["kms:GenerateDataKey"]
    resources = [var.data_kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${local.region}.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "abandoned_cart" {
  statement {
    sid       = "ReadCartsStream"
    actions   = ["dynamodb:DescribeStream", "dynamodb:GetRecords", "dynamodb:GetShardIterator", "dynamodb:ListStreams"]
    resources = [var.carts_stream_arn]
  }

  statement {
    sid       = "DecryptCartsStream"
    actions   = ["kms:Decrypt"]
    resources = [var.data_kms_key_arn]
  }

  statement {
    sid       = "Notify"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.notifications.arn]
  }

  statement {
    sid       = "SendFailures"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.abandoned_carts_dlq.arn]
  }

  statement {
    sid       = "EncryptMessages"
    actions   = ["kms:GenerateDataKey"]
    resources = [var.data_kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["sns.${local.region}.amazonaws.com", "sqs.${local.region}.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "partners" {
  statement {
    sid       = "ReadAndWriteStock"
    actions   = ["dynamodb:Scan", "dynamodb:PutItem"]
    resources = [aws_dynamodb_table.stock.arn]
  }

  statement {
    sid       = "UseDataKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.data_kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["dynamodb.${local.region}.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "daily_report" {
  statement {
    sid       = "ReadStats"
    actions   = ["dynamodb:GetItem"]
    resources = [aws_dynamodb_table.stats.arn]
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
}
