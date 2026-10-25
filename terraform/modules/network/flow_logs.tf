# VPC Flow Logs: quién habla con quién dentro de la VPC (aceptado y rechazado), guardado en un bucket S3 propio. S3 es más barato que CloudWatch Logs y se puede consultar con Athena.

# Creamos un bucket S3 para guardar registros en el sistema:
resource "aws_s3_bucket" "flow_logs" {
  # checkov:skip=CKV_AWS_18:Es el propio bucket de logs; registrar sus accesos sería un bucket de logs de logs.
  # checkov:skip=CKV_AWS_144:Replicación entre regiones innecesaria para logs de dev.
  # checkov:skip=CKV2_AWS_62:Nadie consume eventos de este bucket.
  bucket        = "${var.name}-flow-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.flow_logs_force_destroy

  tags = { Name = "${var.name}-flow-logs" }
}


# Politica de access_block para denegar el acceso publico
resource "aws_s3_bucket_public_access_block" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


resource "aws_s3_bucket_ownership_controls" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.flow_logs_kms_key_arn
    }
    bucket_key_enabled = true
  }
}

#Limpieza automatica de regsitros y backups
resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    id     = "caducar-flow-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.flow_logs_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.flow_logs]
}


# Solo el servicio de logs de AWS, desde esta cuenta, puede escribir; y siempre por HTTPS.
data "aws_iam_policy_document" "flow_logs" {
  statement {
    # AWSLogs/* cubre también las rutas con particiones Hive (AWSLogs/aws-account-id=<cuenta>/...).
    sid       = "AWSLogDeliveryWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.flow_logs.arn}/AWSLogs/*"]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }

  statement {
    sid       = "AWSLogDeliveryCheck"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.flow_logs.arn]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.flow_logs.arn, "${aws_s3_bucket.flow_logs.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json

  depends_on = [aws_s3_bucket_public_access_block.flow_logs]
}

resource "aws_flow_log" "this" {
  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  log_destination_type     = "s3"
  log_destination          = aws_s3_bucket.flow_logs.arn
  max_aggregation_interval = 600

  destination_options {
    file_format                = "parquet" # más pequeño y rápido de consultar con Athena
    hive_compatible_partitions = true
    per_hour_partition         = true
  }

  tags = { Name = "${var.name}-flow-logs" }

  depends_on = [aws_s3_bucket_policy.flow_logs]
}
