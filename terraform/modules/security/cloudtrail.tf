resource "aws_s3_bucket" "cloudtrail" {
  # checkov:skip=CKV_AWS_18:Es el propio bucket de logs; registrar sus accesos sería un bucket de logs de logs.
  # checkov:skip=CKV_AWS_144:Replicación entre regiones innecesaria para logs de dev.
  # checkov:skip=CKV2_AWS_62:Nadie consume eventos de este bucket.


  # CloudTrail sirve para almacenar un registro de actividad en tu cuenta aws. Cada vez que aluguien hace algo, se guarda en el bucket S3 que se crea aqui.


  bucket        = "${var.name}-cloudtrail-${local.account_id}"
  force_destroy = var.force_destroy

  tags = { Name = "${var.name}-cloudtrail" }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.logs.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "caducar-cloudtrail"
    status = "Enabled"

    filter {}

    expiration {
      days = var.cloudtrail_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.cloudtrail]
}

data "aws_iam_policy_document" "cloudtrail_bucket" {
  statement {
    sid       = "CloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]

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
    sid       = "CloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${local.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.cloudtrail.arn, "${aws_s3_bucket.cloudtrail.arn}/*"]

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

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]
}

resource "aws_cloudtrail" "this" {
  # checkov:skip=CKV_AWS_252:Sin aviso SNS por cada fichero nuevo; las alarmas llegan en la fase 7.
  # checkov:skip=CKV2_AWS_10:Sin copia en CloudWatch Logs (coste); se consulta en S3 o en el historial de eventos.
  name           = local.trail_name
  s3_bucket_name = aws_s3_bucket.cloudtrail.id
  kms_key_id     = aws_kms_key.logs.arn

  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  tags = { Name = local.trail_name }

  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
    aws_s3_bucket_server_side_encryption_configuration.cloudtrail,
  ]
}
