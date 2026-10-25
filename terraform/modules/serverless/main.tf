data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  state_machine_name = "${var.name}-order"
  state_machine_arn  = "arn:aws:states:${local.region}:${local.account_id}:stateMachine:${local.state_machine_name}"
}
