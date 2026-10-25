# Configura AWS Backup para hacer copiar de los discos EBS de las instancias EC2

locals {
  backup_tag_value = "${var.name}-ecs"
}

# Donde se guardan las copias
resource "aws_backup_vault" "this" {
  count = var.enable_backup ? 1 : 0

  name          = "${var.name}-vault"
  kms_key_arn   = var.data_kms_key_arn
  force_destroy = var.force_destroy

  tags = { Name = "${var.name}-vault" }
}

# Cuando y cuanto tiempo se guardan las copias
resource "aws_backup_plan" "ebs" {
  count = var.enable_backup ? 1 : 0

  name = "${var.name}-ebs"

  rule {
    rule_name         = "diaria"
    target_vault_name = aws_backup_vault.this[0].name
    schedule          = var.backup_schedule
    start_window      = 60
    completion_window = 180

    lifecycle {
      delete_after = var.backup_retention_days
    }
  }

  tags = { Name = "${var.name}-ebs" }
}

#Politicas y permisos
data "aws_iam_policy_document" "backup_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  count = var.enable_backup ? 1 : 0

  name               = "${var.name}-backup"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json
}

resource "aws_iam_role_policy_attachment" "backup" {
  for_each = var.enable_backup ? toset([
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
  ]) : toset([])

  role       = aws_iam_role.backup[0].name
  policy_arn = each.value
}


# Que se copia
resource "aws_backup_selection" "ebs" {
  count = var.enable_backup ? 1 : 0

  name         = "${var.name}-ebs"
  plan_id      = aws_backup_plan.ebs[0].id
  iam_role_arn = aws_iam_role.backup[0].arn
  resources    = ["arn:aws:ec2:*:*:volume/*"]

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = local.backup_tag_value
  }
}
