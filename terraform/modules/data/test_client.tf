# Esto es una instancia pequeña que comprueba antes de que se ejecute la aplicacion web, que existe la base de datos, el cache y los buckets S3 y que funcionan correctamente.


data "aws_ssm_parameter" "al2023_arm64" {
  count = var.enable_test_client ? 1 : 0

  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_security_group" "test_client" {
  # checkov:skip=CKV2_AWS_5:Va enganchado a aws_instance.test_client (checkov no lo ve por el count).
  count = var.enable_test_client ? 1 : 0

  name        = "${var.name}-test-client"
  description = "Instancia de pruebas: sin entradas; sale a Internet para SSM y paquetes"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-test-client" }
}

resource "aws_vpc_security_group_egress_rule" "test_client_https" {
  count = var.enable_test_client ? 1 : 0

  security_group_id = aws_security_group.test_client[0].id
  description       = "HTTPS para SSM, Secrets Manager y repositorios de paquetes"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

data "aws_iam_policy_document" "test_client_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "test_client" {
  count = var.enable_test_client ? 1 : 0

  name               = "${var.name}-test-client"
  assume_role_policy = data.aws_iam_policy_document.test_client_assume.json
}

resource "aws_iam_role_policy_attachment" "test_client_ssm" {
  count = var.enable_test_client ? 1 : 0

  role       = aws_iam_role.test_client[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "test_client" {
  statement {
    sid       = "ReadDbSecret"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_db_instance.this.master_user_secret[0].secret_arn]
  }

  statement {
    sid       = "DecryptDbSecret"
    actions   = ["kms:Decrypt"]
    resources = [var.data_kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${local.region}.amazonaws.com"]
    }
  }

  statement {
    sid       = "UseCarts"
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"]
    resources = [aws_dynamodb_table.carts.arn]
  }

  statement {
    sid       = "UseBuckets"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = flatten([for b in aws_s3_bucket.this : [b.arn, "${b.arn}/*"]])
  }

  statement {
    sid       = "UseDataKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.data_kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["dynamodb.${local.region}.amazonaws.com", "s3.${local.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "test_client" {
  count = var.enable_test_client ? 1 : 0

  name   = "data-access"
  role   = aws_iam_role.test_client[0].id
  policy = data.aws_iam_policy_document.test_client.json
}

resource "aws_iam_instance_profile" "test_client" {
  count = var.enable_test_client ? 1 : 0

  name = "${var.name}-test-client"
  role = aws_iam_role.test_client[0].name
}

resource "aws_instance" "test_client" {
  # checkov:skip=CKV_AWS_126:Monitorización detallada innecesaria en una instancia de pruebas (coste).
  count = var.enable_test_client ? 1 : 0

  ami                    = data.aws_ssm_parameter.al2023_arm64[0].insecure_value
  instance_type          = var.test_client_instance_type
  subnet_id              = var.app_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.test_client[0].id, aws_security_group.clients.id]
  iam_instance_profile   = aws_iam_instance_profile.test_client[0].name
  ebs_optimized          = true

  user_data_replace_on_change = true
  user_data                   = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    dnf install -y jq
    dnf install -y postgresql17 || dnf install -y postgresql16 || dnf install -y postgresql15
    dnf install -y valkey || dnf install -y redis6 || true
  EOF

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  tags = { Name = "${var.name}-test-client" }

  lifecycle {
    ignore_changes = [ami]
  }
}
