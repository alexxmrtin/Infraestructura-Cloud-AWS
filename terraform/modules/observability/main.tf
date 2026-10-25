data "aws_region" "current" {}

locals {
  region         = data.aws_region.current.region
  dashboard_name = "${var.name}-shopflow"
  alarm_actions  = [var.alarm_topic_arn]

  metrics_dimension = ["Environment", var.name]
  state_machine     = ["StateMachineArn", var.state_machine_arn]
  alb               = ["LoadBalancer", var.alb_arn_suffix]
  ecs_service       = ["ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name]
  partners_api      = ["ApiName", var.partners_api_name, "Stage", var.partners_api_stage]

  lambda_log_groups = values(var.lambda_log_group_names)
}
