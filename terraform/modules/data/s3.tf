# Tenemos tres buckets en S3, images,uploads y invoices.Invoices son para facturas en pdf

locals {
  buckets = {
    images = {
      expiration_days    = null
      transition_ia_days = null
    }
    uploads = {
      expiration_days    = var.uploads_retention_days
      transition_ia_days = null
    }
    invoices = {
      expiration_days    = null
      transition_ia_days = 30
    }
  }
}

# Creacion del bucket
resource "aws_s3_bucket" "this" {
  # checkov:skip=CKV_AWS_18:Sin registro de accesos en dev (otro bucket y más coste); CloudTrail ya apunta quién toca cada bucket.
  # checkov:skip=CKV_AWS_144:Replicación entre regiones innecesaria en dev.
  # checkov:skip=CKV2_AWS_62:Los avisos de eventos (p. ej. una subida nueva) llegan en la fase 6.
  # checkov:skip=CKV2_AWS_6:El bloqueo de acceso público está más abajo con el mismo for_each; checkov solo lo enlaza con el primer bucket.
  # checkov:skip=CKV2_AWS_61:Ídem con la configuración de ciclo de vida.
  # checkov:skip=CKV_AWS_21:Ídem con el versionado.
  # checkov:skip=CKV_AWS_145:Ídem con el cifrado SSE-KMS.
  for_each = local.buckets

  bucket        = "${var.name}-${each.key}-${local.account_id}"
  force_destroy = var.force_destroy

  tags = { Name = "${var.name}-${each.key}" }
}

# Denagamos acceso publico con esta politica
resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.data_kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    id     = "limpieza-${each.key}"
    status = "Enabled"

    filter {}

    dynamic "expiration" {
      for_each = local.buckets[each.key].expiration_days == null ? [] : [local.buckets[each.key].expiration_days]

      content {
        days = expiration.value
      }
    }

    dynamic "transition" {
      for_each = local.buckets[each.key].transition_ia_days == null ? [] : [local.buckets[each.key].transition_ia_days]

      content {
        days          = transition.value
        storage_class = "STANDARD_IA"
      }
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

data "aws_iam_policy_document" "bucket" {
  for_each = aws_s3_bucket.this

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [each.value.arn, "${each.value.arn}/*"]

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

resource "aws_s3_bucket_policy" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id
  policy = data.aws_iam_policy_document.bucket[each.key].json

  depends_on = [aws_s3_bucket_public_access_block.this]
}
