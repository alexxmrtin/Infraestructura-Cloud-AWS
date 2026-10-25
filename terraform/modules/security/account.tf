

# Guardduty es un servicio el cual lee CloudTrail (el registro de actividad en aws),los registros de red (FlowLogs) y las consultas DNS
resource "aws_guardduty_detector" "this" {
  # checkov:skip=CKV2_AWS_3:Cuenta personal sin AWS Organizations; no hay configuración de organización que activar.
  count = var.enable_guardduty ? 1 : 0

  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = { Name = "${var.name}-guardduty" }
}


# Servicio que revisa todas las politicas de la cuenta. En este caso lo configuramos para que encuentre politicas que permitan acceso publico y lo denegamos en caso de que encuentre algo.
resource "aws_accessanalyzer_analyzer" "this" {
  count = var.enable_access_analyzer ? 1 : 0

  analyzer_name = "${var.name}-access-analyzer"
  type          = "ACCOUNT"

  tags = { Name = "${var.name}-access-analyzer" }
}

# Cualquier disco que se crea en la region se cifra. Por ejemplo los discos EBS de las instancias EC2.
resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}
