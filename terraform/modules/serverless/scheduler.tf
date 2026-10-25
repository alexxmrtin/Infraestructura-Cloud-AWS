data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${var.name}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

data "aws_iam_policy_document" "scheduler" {
  statement {
    sid       = "InvokeDailyReport"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.this["daily_report"].arn]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "daily-report"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler.json
}

resource "aws_scheduler_schedule" "daily_report" {
  # checkov:skip=CKV_AWS_297:El aviso no lleva datos que cifrar (la entrada es {}); con la clave de AWS basta.
  name                         = "${var.name}-daily-report"
  description                  = "Resumen de pedidos del dia anterior por email"
  schedule_expression          = var.daily_report_schedule
  schedule_expression_timezone = var.schedule_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.this["daily_report"].arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({})

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
  }
}
