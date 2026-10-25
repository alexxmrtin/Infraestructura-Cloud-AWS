#Este archivo crea el dashboard de CloudWatch. Cada bloque { type = ... } es una caja del dashboard: texto, grafica, alarmas o logs. x e y son la posicion y width y height el tamaño (el ancho total es 24)

locals {
  #Namespace de las metricas propias de la tienda
  shopflow_metrics = [var.metrics_namespace]

  #Lista de todas las cajas del dashboard, de arriba abajo. Son varias listas unidas con concat
  widgets = concat(
    [
      #Cabecera del dashboard: titulo y una linea explicando donde mirar
      {
        type = "text", x = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "# ShopFlow (${var.name})\nPedidos, web, API, datos y serverless. Las alarmas mandan un email al tema de avisos de la tienda. Los logs se buscan en **Logs Insights**."
        }
      },
      #Numeros grandes: pedidos, importe, confirmados y rechazados en el periodo que elijas arriba
      {
        type = "metric", x = 0, y = 2, width = 12, height = 4
        properties = {
          title                = "Pedidos en el periodo elegido"
          view                 = "singleValue"
          region               = local.region
          stat                 = "Sum"
          period               = 300
          setPeriodToTimeRange = true
          metrics = [
            concat(local.shopflow_metrics, ["OrdersPlaced"], local.metrics_dimension, [{ label = "Pedidos" }]),
            concat(local.shopflow_metrics, ["OrderValue"], local.metrics_dimension, [{ label = "Importe (EUR)" }]),
            concat(["AWS/States", "ExecutionsSucceeded"], local.state_machine, [{ label = "Confirmados" }]),
            concat(["AWS/States", "ExecutionsFailed"], local.state_machine, [{ label = "Rechazados" }]),
          ]
        }
      },
      #Estado de todas las alarmas (verde OK, rojo ALARM)
      {
        type = "alarm", x = 12, y = 2, width = 12, height = 4
        properties = {
          title  = "Alarmas"
          sortBy = "stateUpdatedTimestamp"
          alarms = local.alarm_arns
        }
      },
      #Grafica de pedidos nuevos, confirmados y rechazados cada 5 minutos
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "Pedidos cada 5 minutos"
          view   = "timeSeries"
          region = local.region
          stat   = "Sum"
          period = 300
          metrics = [
            concat(local.shopflow_metrics, ["OrdersPlaced"], local.metrics_dimension, [{ label = "Nuevos" }]),
            concat(["AWS/States", "ExecutionsSucceeded"], local.state_machine, [{ label = "Confirmados" }]),
            concat(["AWS/States", "ExecutionsFailed"], local.state_machine, [{ label = "Rechazados" }]),
          ]
        }
      },
      #Grafica de los motivos de rechazo: pago rechazado o sin stock (metricas propias)
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "Por qué se rechazan"
          view   = "timeSeries"
          region = local.region
          stat   = "Sum"
          period = 300
          metrics = [
            concat(local.shopflow_metrics, ["PaymentsDeclined"], local.metrics_dimension, [{ label = "Pago rechazado" }]),
            concat(local.shopflow_metrics, ["OutOfStock"], local.metrics_dimension, [{ label = "Sin stock" }]),
          ]
        }
      },
      #Titulo de la seccion web
      {
        type       = "text", x = 0, y = 12, width = 24, height = 1
        properties = { markdown = "## Web: CloudFront, WAF y ALB (CloudFront y WAF son globales: sus métricas están en us-east-1)" }
      },
      #Peticiones que recibe CloudFront (sus metricas estan en us-east-1)
      {
        type = "metric", x = 0, y = 13, width = 8, height = 6
        properties = {
          title  = "CloudFront: peticiones"
          view   = "timeSeries"
          region = "us-east-1"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/CloudFront", "Requests", "DistributionId", var.distribution_id, "Region", "Global", { label = "Peticiones" }],
          ]
        }
      },
      #Porcentaje de respuestas 4xx y 5xx de CloudFront
      {
        type = "metric", x = 8, y = 13, width = 8, height = 6
        properties = {
          title  = "CloudFront: % de errores"
          view   = "timeSeries"
          region = "us-east-1"
          stat   = "Average"
          period = 300
          metrics = [
            ["AWS/CloudFront", "4xxErrorRate", "DistributionId", var.distribution_id, "Region", "Global", { label = "4xx" }],
            ["AWS/CloudFront", "5xxErrorRate", "DistributionId", var.distribution_id, "Region", "Global", { label = "5xx" }],
          ]
        }
      },
    ],
    #Lista que solo se incluye si hay WAF (si web_acl_name es null queda vacia)
    [for w in [
      #Peticiones que el WAF deja pasar y las que bloquea. Solo aparece si el WAF esta encendido
      {
        type = "metric", x = 16, y = 13, width = 8, height = 6
        properties = {
          title  = "WAF: permitidas y bloqueadas"
          view   = "timeSeries"
          region = "us-east-1"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/WAFV2", "AllowedRequests", "WebACL", var.web_acl_name, "Rule", "ALL", { label = "Permitidas" }],
            ["AWS/WAFV2", "BlockedRequests", "WebACL", var.web_acl_name, "Rule", "ALL", { label = "Bloqueadas" }],
          ]
        }
      },
    ] : w if var.web_acl_name != null],
    [
      #Peticiones que llegan al ALB y cuantas acaban en 4xx o 5xx
      {
        type = "metric", x = 0, y = 19, width = 12, height = 6
        properties = {
          title  = "ALB: peticiones y errores de la API"
          view   = "timeSeries"
          region = local.region
          stat   = "Sum"
          period = 300
          metrics = [
            concat(["AWS/ApplicationELB", "RequestCount"], local.alb, [{ label = "Peticiones" }]),
            concat(["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count"], local.alb, [{ label = "4xx" }]),
            concat(["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count"], local.alb, [{ label = "5xx" }]),
          ]
        }
      },
      #Cuanto tarda la API en contestar (p95) y cuantas tareas sanas tiene el ALB
      {
        type = "metric", x = 12, y = 19, width = 12, height = 6
        properties = {
          title  = "ALB: tiempo de respuesta (p95) y tareas sanas"
          view   = "timeSeries"
          region = local.region
          period = 60
          metrics = [
            concat(["AWS/ApplicationELB", "TargetResponseTime"], local.alb, [{ stat = "p95", label = "Respuesta p95 (s)" }]),
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", var.target_group_arn_suffix, "LoadBalancer", var.alb_arn_suffix, { stat = "Minimum", label = "Tareas sanas", yAxis = "right" }],
          ]
        }
      },
      #Titulo de la seccion API y datos
      {
        type       = "text", x = 0, y = 25, width = 24, height = 1
        properties = { markdown = "## API y datos: ECS y RDS" }
      },
      #CPU y memoria que usan las tareas de la API en ECS
      {
        type = "metric", x = 0, y = 26, width = 8, height = 6
        properties = {
          title  = "ECS: CPU y memoria de la API (%)"
          view   = "timeSeries"
          region = local.region
          stat   = "Average"
          period = 60
          metrics = [
            concat(["AWS/ECS", "CPUUtilization"], local.ecs_service, [{ label = "CPU" }]),
            concat(["AWS/ECS", "MemoryUtilization"], local.ecs_service, [{ label = "Memoria" }]),
          ]
        }
      },
      #Tareas de la API funcionando frente a las que deberia haber
      {
        type = "metric", x = 8, y = 26, width = 8, height = 6
        properties = {
          title  = "ECS: tareas de la API"
          view   = "timeSeries"
          region = local.region
          stat   = "Average"
          period = 60
          metrics = [
            concat(["ECS/ContainerInsights", "RunningTaskCount"], local.ecs_service, [{ label = "Funcionando" }]),
            concat(["ECS/ContainerInsights", "DesiredTaskCount"], local.ecs_service, [{ label = "Deseadas" }]),
          ]
        }
      },
      #CPU y conexiones abiertas de RDS
      {
        type = "metric", x = 16, y = 26, width = 8, height = 6
        properties = {
          title  = "RDS: CPU y conexiones"
          view   = "timeSeries"
          region = local.region
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_id, { label = "CPU (%)" }],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_instance_id, { label = "Conexiones", yAxis = "right" }],
          ]
        }
      },
      #Titulo de la seccion serverless
      {
        type       = "text", x = 0, y = 32, width = 24, height = 1
        properties = { markdown = "## Serverless: Lambdas, colas, Step Functions y API de partners" }
      },
      #Cuantas veces se ejecuta cada Lambda
      {
        type = "metric", x = 0, y = 33, width = 12, height = 6
        properties = {
          title   = "Lambdas: ejecuciones"
          view    = "timeSeries"
          region  = local.region
          stat    = "Sum"
          period  = 300
          metrics = [for k, f in var.lambda_function_names : ["AWS/Lambda", "Invocations", "FunctionName", f, { label = k }]]
        }
      },
      #Errores de cada Lambda
      {
        type = "metric", x = 12, y = 33, width = 12, height = 6
        properties = {
          title   = "Lambdas: errores (payment y stock fallan a propósito al rechazar un pedido)"
          view    = "timeSeries"
          region  = local.region
          stat    = "Sum"
          period  = 300
          metrics = [for k, f in var.lambda_function_names : ["AWS/Lambda", "Errors", "FunctionName", f, { label = k }]]
        }
      },
      #Mensajes en las colas de errores (DLQ). Lo normal es 0
      {
        type = "metric", x = 0, y = 39, width = 8, height = 6
        properties = {
          title   = "Colas de errores (DLQ): mensajes"
          view    = "timeSeries"
          region  = local.region
          stat    = "Maximum"
          period  = 300
          metrics = [for k, q in var.dlq_names : ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", q, { label = k }]]
        }
      },
      #Cuanto tarda cada pedido en Step Functions (media y maximo)
      {
        type = "metric", x = 8, y = 39, width = 8, height = 6
        properties = {
          title  = "Step Functions: duración de cada pedido (ms)"
          view   = "timeSeries"
          region = local.region
          period = 300
          metrics = [
            concat(["AWS/States", "ExecutionTime"], local.state_machine, [{ stat = "Average", label = "Media" }]),
            concat(["AWS/States", "ExecutionTime"], local.state_machine, [{ stat = "Maximum", label = "Máxima" }]),
          ]
        }
      },
      #Peticiones a la API de partners y sus errores 4xx y 5xx
      {
        type = "metric", x = 16, y = 39, width = 8, height = 6
        properties = {
          title  = "API de partners"
          view   = "timeSeries"
          region = local.region
          stat   = "Sum"
          period = 300
          metrics = [
            concat(["AWS/ApiGateway", "Count"], local.partners_api, [{ label = "Peticiones" }]),
            concat(["AWS/ApiGateway", "4XXError"], local.partners_api, [{ label = "4xx" }]),
            concat(["AWS/ApiGateway", "5XXError"], local.partners_api, [{ label = "5xx" }]),
          ]
        }
      },
      #Tabla con las ultimas lineas de log de las Lambdas que dicen error (consulta de Logs Insights)
      {
        type = "log", x = 0, y = 45, width = 24, height = 6
        properties = {
          title  = "Últimos errores de las Lambdas"
          region = local.region
          view   = "table"
          query  = "${join(" | ", [for g in local.lambda_log_groups : "SOURCE '${g}'"])} | fields @timestamp, @log, @message | filter @message like /(?i)error|traceback/ | sort @timestamp desc | limit 20"
        }
      },
    ],
  )

  #Las alarmas que salen en la caja de alarmas: todas las de alarms.tf
  alarm_arns = concat(
    [for a in aws_cloudwatch_metric_alarm.dlq : a.arn],
    [for a in aws_cloudwatch_metric_alarm.lambda_errors : a.arn],
    [
      aws_cloudwatch_metric_alarm.api_unhealthy.arn,
      aws_cloudwatch_metric_alarm.api_5xx.arn,
      aws_cloudwatch_metric_alarm.rds_cpu.arn,
      aws_cloudwatch_metric_alarm.rds_storage.arn,
      aws_cloudwatch_metric_alarm.partners_5xx.arn,
      aws_cloudwatch_metric_alarm.payments_declined.arn,
    ],
  )
}

#El dashboard en si: nombre y contenido. jsonencode convierte la lista de cajas en el JSON que pide CloudWatch
resource "aws_cloudwatch_dashboard" "shopflow" {
  dashboard_name = local.dashboard_name
  dashboard_body = jsonencode({ widgets = local.widgets })
}
