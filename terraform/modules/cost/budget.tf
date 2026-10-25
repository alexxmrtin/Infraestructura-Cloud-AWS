#Presupuesto mensual solo de este entorno: avisa por email si se gasta demasiado.
#Vive y muere con el entorno; el de toda la cuenta sigue en el bootstrap.

#El presupuesto. Si no hay email no se crea (count = 0), porque no tendria a quien avisar
resource "aws_budgets_budget" "environment" {
  count = local.email_alerts ? 1 : 0

  #Nombre, tipo (dinero), limite en USD, cada cuanto se reinicia (mes) y que coste mide
  name         = var.name
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  metrics      = ["UnblendedCost"]

  #Solo cuenta lo que tenga las dos etiquetas: Project = infra-cloud-aws y Environment = dev
  #Las etiquetas las pone default_tags del provider en todos los recursos
  filter_expression {
    and {
      tags {
        key    = "Project"
        values = [var.project]
      }
    }

    and {
      tags {
        key    = "Environment"
        values = [var.environment]
      }
    }
  }

  #Crea un aviso por cada elemento de budget_alerts (main.tf): 50 % y 100 % real, 100 % previsto
  #Previsto = a cuanto llegaras a fin de mes si sigues gastando igual
  dynamic "notification" {
    for_each = local.budget_alerts

    content {
      notification_type          = notification.value.type
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value.threshold
      threshold_type             = "PERCENTAGE"
      subscriber_email_addresses = [var.notification_email]
    }
  }
}
