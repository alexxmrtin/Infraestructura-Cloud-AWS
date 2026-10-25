#Recordatorio de apagado: cada noche a las 22:00 manda "el entorno sigue encendido" al tema de avisos.
#Como se destruye con el entorno, el email solo llega si te has olvidado de hacer destroy.

#Quien puede usar el rol: solo EventBridge Scheduler y solo desde esta cuenta
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

#El rol que usa el Scheduler para mandar el aviso (no se crea si enable_reminder = false)
resource "aws_iam_role" "reminder" {
  count = var.enable_reminder ? 1 : 0

  name               = "${var.name}-still-on-reminder"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

#Lo que puede hacer el rol: publicar en el tema de avisos y usar la llave data,
#porque el tema esta cifrado con ella y sin la llave no podria dejar el mensaje
data "aws_iam_policy_document" "reminder" {
  statement {
    sid       = "PublishReminder"
    actions   = ["sns:Publish"]
    resources = [var.notification_topic_arn]
  }

  statement {
    sid       = "EncryptedTopic"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = [var.data_kms_key_arn]
  }
}

#Pega esos permisos al rol
resource "aws_iam_role_policy" "reminder" {
  count = var.enable_reminder ? 1 : 0

  name   = "still-on-reminder"
  role   = aws_iam_role.reminder[0].id
  policy = data.aws_iam_policy_document.reminder.json
}

#El despertador: cuando salta (22:00 hora de Madrid) y que hace (publicar el texto en el tema)
resource "aws_scheduler_schedule" "still_on" {
  # checkov:skip=CKV_AWS_297:El aviso solo lleva un texto fijo; con la clave de AWS basta.
  count = var.enable_reminder ? 1 : 0

  name                         = "${var.name}-still-on"
  description                  = "Aviso por email de que el entorno sigue encendido"
  schedule_expression          = var.reminder_schedule
  schedule_expression_timezone = var.schedule_timezone

  #OFF = salta a la hora exacta, sin margen de unos minutos
  flexible_time_window {
    mode = "OFF"
  }

  #A donde va el aviso (el tema de avisos), con que rol y el texto del email
  target {
    arn      = var.notification_topic_arn
    role_arn = aws_iam_role.reminder[0].arn
    input    = "El entorno ${var.name} sigue encendido y cuesta unos ${var.daily_cost_usd} USD al dia. Si ya has terminado, destruyelo: GitHub > Actions > terraform > Run workflow > destroy."

    #Si falla lo reintenta 2 veces durante como mucho una hora
    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
  }
}
