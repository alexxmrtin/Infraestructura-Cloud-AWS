#Cost Anomaly Detection: AWS aprende cuanto gasta este entorno y avisa si un dia gasta mucho mas.
#Dos piezas: el monitor (que vigila) y la suscripcion (a quien avisa y desde cuanto).

#El monitor. CUSTOM = vigilamos un gasto elegido por nosotros, no todos los servicios de la cuenta
resource "aws_ce_anomaly_monitor" "environment" {
  count = local.email_alerts ? 1 : 0

  name         = var.name
  monitor_type = "CUSTOM"

  #Que gasto vigila: lo que tenga Project = infra-cloud-aws y Environment = dev (en JSON)
  #Los campos a null los pide AWS asi; sin ellos Terraform veria cambios en cada plan
  monitor_specification = jsonencode({
    And            = null
    CostCategories = null
    Dimensions     = null
    Not            = null
    Or             = null
    Tags = {
      Key          = "Environment"
      MatchOptions = null
      Values       = [var.environment]
    }
  })
}

#La suscripcion: una vez al dia manda por email las anomalias del monitor de arriba
resource "aws_ce_anomaly_subscription" "environment" {
  count = local.email_alerts ? 1 : 0

  name             = var.name
  frequency        = "DAILY"
  monitor_arn_list = [aws_ce_anomaly_monitor.environment[0].arn]

  #A quien avisa: tu email (notification_email)
  subscriber {
    type    = "EMAIL"
    address = var.notification_email
  }

  #Solo avisa si la anomalia ha costado 3 USD o mas de lo normal (anomaly_threshold_usd)
  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.anomaly_threshold_usd)]
    }
  }
}
