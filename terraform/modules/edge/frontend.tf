# Este archivo crea el bucket de la web y sube los ficheros al bucket. Son dos bloques, el primero es la creacion del bucket con sus politicas internas ,  el segundo son politicas de permisos.


locals {
  content_types = {
    html = "text/html; charset=utf-8"
    css  = "text/css; charset=utf-8"
    js   = "text/javascript; charset=utf-8"
    svg  = "image/svg+xml"
    png  = "image/png"
    ico  = "image/x-icon"
  }

  frontend_files = fileset(var.frontend_dir, "**/*.{html,css,js,svg,png,ico}")
}

# Creacion del bucket
resource "aws_s3_bucket" "frontend" {
  # checkov:skip=CKV_AWS_18:Sin registro de accesos en dev; las peticiones se ven en CloudFront y en el WAF.
  # checkov:skip=CKV_AWS_144:Replicación entre regiones innecesaria: la web se vuelve a subir en cada apply.
  # checkov:skip=CKV2_AWS_62:No hace falta avisar de cambios en la web.
  # checkov:skip=CKV_AWS_145:La web es pública; SSE-S3 evita dar a CloudFront permiso sobre la clave data.
  bucket        = "${var.name}-frontend-${local.account_id}"
  force_destroy = true

  tags = { Name = "${var.name}-frontend" }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# politica, todos los ficheros son del dueño del bucket
resource "aws_s3_bucket_ownership_controls" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    id     = "versiones-antiguas"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.frontend]
}



# Politicas de permisos, quien puede hacer que
data "aws_iam_policy_document" "frontend" {
  statement {
    sid       = "CloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.shop.arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.frontend.arn, "${aws_s3_bucket.frontend.arn}/*"]

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

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend.json

  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

resource "aws_s3_object" "frontend" {
  for_each = local.frontend_files

  bucket        = aws_s3_bucket.frontend.id
  key           = each.value
  source        = "${var.frontend_dir}/${each.value}"
  source_hash   = filemd5("${var.frontend_dir}/${each.value}")
  content_type  = local.content_types[reverse(split(".", each.value))[0]]
  cache_control = "max-age=60"
}

resource "aws_s3_object" "config" {
  bucket        = aws_s3_bucket.frontend.id
  key           = "config.js"
  content_type  = local.content_types.js
  cache_control = "no-cache"

  content = "window.SHOPFLOW_CONFIG = ${jsonencode({
    region      = local.region
    userPoolId  = aws_cognito_user_pool.this.id
    clientId    = aws_cognito_user_pool_client.web.id
    authDomain  = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${local.region}.amazoncognito.com"
    redirectUri = "${local.shop_url}/"
  })};\n"
}
