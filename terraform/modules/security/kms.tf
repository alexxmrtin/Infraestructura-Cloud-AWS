data "aws_iam_policy_document" "logs_key" {
  # checkov:skip=CKV_AWS_109:En una política de clave, "*" es la propia clave; es la declaración estándar de AWS.
  # checkov:skip=CKV_AWS_111:Ídem: el acceso de la cuenta se controla después con IAM.
  # checkov:skip=CKV_AWS_356:Ídem: en una política de clave el recurso siempre es "*".


  # Este archivo se usa para crear las dos llaves, para los logs y para los datos. Estas llaves cifran un contenido determinado que almacena en un sitio, por ejemplo un bucket S3, y solo con esas llaves se pueden descrifrar. 



  # Hay una llave que se usa para tres servicios que tiene que ver con los logs. Son CloudTrail,Flow Logs y  Cloud watch. 

  #CloudTrail: apunta todo lo que se hace en tu cuenta de AWS (quién, qué y cuándo).

  #Flow Logs: apunta qué conexiones de red entran y salen de tu VPC.

  #CloudWatch Logs: guarda los mensajes que escriben tus programas (contenedores y Lambdas) mientras funcionan.

  statement {
    sid       = "EnableIAMPolicies"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "CloudTrailEncrypt"
    actions   = ["kms:GenerateDataKey*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:aws:cloudtrail:*:${local.account_id}:trail/*"]
    }
  }


  statement {
    sid       = "CloudTrailDescribe"
    actions   = ["kms:DescribeKey"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }


  statement {
    sid       = "FlowLogsDelivery"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:${local.region}:${local.account_id}:*"]
    }
  }


  statement {
    sid       = "CloudWatchLogs"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${local.region}:${local.account_id}:*"]
    }
  }
}


# La llave logs

resource "aws_kms_key" "logs" {
  description             = "${var.name}: CloudTrail, Flow Logs y CloudWatch Logs"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
  policy                  = data.aws_iam_policy_document.logs_key.json

  tags = { Name = "${var.name}-logs" }
}

resource "aws_kms_alias" "logs" {
  name          = "alias/${var.name}-logs"
  target_key_id = aws_kms_key.logs.key_id
}


# La llave data

data "aws_iam_policy_document" "data_key" {
  # checkov:skip=CKV_AWS_109:En una política de clave, "*" es la propia clave; es la declaración estándar de AWS.
  # checkov:skip=CKV_AWS_111:Ídem: el acceso de la cuenta se controla después con IAM.
  # checkov:skip=CKV_AWS_356:Ídem: en una política de clave el recurso siempre es "*".
  statement {
    sid       = "EnableIAMPolicies"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "AutoScalingUseKey"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = [local.autoscaling_role_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "AutoScalingCreateGrant"
    actions   = ["kms:CreateGrant"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = [local.autoscaling_role_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  statement {
    sid       = "SnsToEncryptedQueues"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "CloudWatchAlarmsToSns"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "data" {
  description             = "${var.name}: datos de la aplicacion (RDS, DynamoDB, S3, secretos)"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
  policy                  = data.aws_iam_policy_document.data_key.json

  tags = { Name = "${var.name}-data" }
}

resource "aws_kms_alias" "data" {
  name          = "alias/${var.name}-data"
  target_key_id = aws_kms_key.data.key_id
}
