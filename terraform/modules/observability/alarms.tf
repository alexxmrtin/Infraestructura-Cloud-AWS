#Este archivo crea las alarmas de CloudWatch. Todas mandan un email al tema SNS de avisos cuando saltan (ALARM) y cuando se arreglan (OK)

#Una alarma por cada cola de errores (DLQ). Salta si hay algun mensaje: algo ha fallado 3 veces seguidas
resource "aws_cloudwatch_metric_alarm" "dlq" {
  for_each = var.dlq_names

  alarm_name          = "${each.value}-con-mensajes"
  alarm_description   = "Hay mensajes en la cola de errores ${each.value}: algo ha fallado 3 veces seguidas. Míralos en la consola de SQS."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = each.value }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  tags = { Name = "${each.value}-con-mensajes" }
}

#Una alarma por Lambda (menos payment y stock, que fallan a proposito al rechazar un pedido). Salta con 1 error en 5 minutos
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = toset(var.alarmed_lambdas)

  alarm_name          = "${var.lambda_function_names[each.key]}-errores"
  alarm_description   = "La Lambda ${var.lambda_function_names[each.key]} ha fallado. Mira sus logs en CloudWatch o la tabla de últimos errores del dashboard."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = var.lambda_function_names[each.key] }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  tags = { Name = "${var.lambda_function_names[each.key]}-errores" }
}

#Salta si el ALB lleva 10 minutos sin ninguna tarea sana de la API, es decir, la tienda no responde
resource "aws_cloudwatch_metric_alarm" "api_unhealthy" {
  alarm_name          = "${var.name}-api-sin-tareas-sanas"
  alarm_description   = "El ALB no tiene ninguna tarea sana de la API desde hace ${var.api_unhealthy_minutes} minutos: la tienda no responde. Mira el servicio en ECS."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  dimensions          = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffix }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = var.api_unhealthy_minutes
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  tags = { Name = "${var.name}-api-sin-tareas-sanas" }
}

#Salta si la API contesta 5 o mas errores 5xx (fallos del servidor) en 5 minutos
resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.name}-api-errores-5xx"
  alarm_description   = "La API ha contestado ${var.api_5xx_threshold} o más errores 5xx en 5 minutos. Mira los logs de la API en CloudWatch."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffix }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.api_5xx_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  tags = { Name = "${var.name}-api-errores-5xx" }
}

#Salta si la CPU de RDS pasa del 80 % durante 15 minutos (3 periodos de 5 minutos)
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.name}-rds-cpu-alta"
  alarm_description   = "RDS lleva 15 minutos por encima del ${var.rds_cpu_threshold} % de CPU."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = var.db_instance_id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.rds_cpu_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  tags = { Name = "${var.name}-rds-cpu-alta" }
}

#Salta si al disco de RDS le quedan menos de 2 GB libres
resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${var.name}-rds-poco-disco"
  alarm_description   = "Al disco de RDS le quedan menos de ${var.rds_free_storage_threshold_gb} GB libres."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = var.db_instance_id }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.rds_free_storage_threshold_gb * 1024 * 1024 * 1024
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  tags = { Name = "${var.name}-rds-poco-disco" }
}

#Salta si la API de partners (API Gateway) devuelve algun error 5xx
resource "aws_cloudwatch_metric_alarm" "partners_5xx" {
  alarm_name          = "${var.name}-partners-errores-5xx"
  alarm_description   = "La API de partners ha contestado errores 5xx. Mira los logs de acceso de la API de partners en CloudWatch."
  namespace           = "AWS/ApiGateway"
  metric_name         = "5XXError"
  dimensions          = { ApiName = var.partners_api_name, Stage = var.partners_api_stage }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  tags = { Name = "${var.name}-partners-errores-5xx" }
}

#Alarma sobre una metrica propia: salta con 5 o mas pagos rechazados en una hora
resource "aws_cloudwatch_metric_alarm" "payments_declined" {
  alarm_name          = "${var.name}-muchos-pagos-rechazados"
  alarm_description   = "Se han rechazado ${var.payments_declined_threshold} o más pagos en una hora (métrica propia PaymentsDeclined)."
  namespace           = var.metrics_namespace
  metric_name         = "PaymentsDeclined"
  dimensions          = { Environment = var.name }
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 1
  threshold           = var.payments_declined_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  tags = { Name = "${var.name}-muchos-pagos-rechazados" }
}
