output "dashboard_name" {
  description = "Nombre del dashboard de CloudWatch."
  value       = aws_cloudwatch_dashboard.shopflow.dashboard_name
}

output "dashboard_url" {
  description = "Enlace directo al dashboard en la consola."
  value       = "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.shopflow.dashboard_name}"
}

output "alarm_names" {
  description = "Nombres de todas las alarmas."
  value = concat(
    [for a in aws_cloudwatch_metric_alarm.dlq : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.lambda_errors : a.alarm_name],
    [
      aws_cloudwatch_metric_alarm.api_unhealthy.alarm_name,
      aws_cloudwatch_metric_alarm.api_5xx.alarm_name,
      aws_cloudwatch_metric_alarm.rds_cpu.alarm_name,
      aws_cloudwatch_metric_alarm.rds_storage.alarm_name,
      aws_cloudwatch_metric_alarm.partners_5xx.alarm_name,
      aws_cloudwatch_metric_alarm.payments_declined.alarm_name,
    ],
  )
}
