data "aws_caller_identity" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  email_alerts = var.notification_email != ""

  budget_alerts = {
    actual_50      = { type = "ACTUAL", threshold = 50 }
    actual_100     = { type = "ACTUAL", threshold = 100 }
    forecasted_100 = { type = "FORECASTED", threshold = 100 }
  }
}
