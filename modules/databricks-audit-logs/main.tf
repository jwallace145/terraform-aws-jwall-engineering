locals {
  # Databricks' AWS account that assumes customer roles for log delivery.
  databricks_account_arn = "arn:aws:iam::414351767826:root"

  object_actions = [
    "s3:PutObject",
    "s3:GetObject",
    "s3:DeleteObject",
    "s3:PutObjectAcl",
    "s3:AbortMultipartUpload",
    "s3:ListMultipartUploadParts",
  ]

  # Everything Databricks may touch lives under one prefix; the only
  # bucket-level right is GetBucketLocation.
  delivery_statements = [
    {
      Effect   = "Allow"
      Action   = "s3:GetBucketLocation"
      Resource = aws_s3_bucket.this.arn
    },
    {
      Effect   = "Allow"
      Action   = local.object_actions
      Resource = "${aws_s3_bucket.this.arn}/${var.prefix}/*"
    },
  ]
}

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name

  tags = {
    Name      = var.bucket_name
    Component = var.component
  }

  # No force_destroy: audit logs are a record, not scratch data.
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_iam_role" "log_delivery" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = local.databricks_account_arn }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.account_id
          }
        }
      },
    ]
  })

  tags = {
    Name      = var.role_name
    Component = var.component
  }
}

resource "aws_iam_role_policy" "log_delivery" {
  name = "write-audit-logs"
  role = aws_iam_role.log_delivery.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.delivery_statements
  })
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id

  # Databricks' documented log-delivery grants for the delivery role, plus a
  # TLS-only deny. There is deliberately no other Deny: the account's own
  # principals (for example CI roles writing events/) keep their IAM-granted
  # access to every other prefix.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid       = "DenyInsecureTransport"
          Effect    = "Deny"
          Principal = "*"
          Action    = "s3:*"
          Resource = [
            aws_s3_bucket.this.arn,
            "${aws_s3_bucket.this.arn}/*",
          ]
          Condition = {
            Bool = {
              "aws:SecureTransport" = "false"
            }
          }
        },
      ],
      [
        for s in local.delivery_statements :
        merge(s, { Principal = { AWS = aws_iam_role.log_delivery.arn } })
      ],
    )
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}

resource "databricks_mws_credentials" "log_delivery" {
  credentials_name = var.role_name
  role_arn         = aws_iam_role.log_delivery.arn

  # IAM is eventually consistent; Databricks validates the role on create.
  depends_on = [aws_iam_role_policy.log_delivery]
}

resource "databricks_mws_storage_configurations" "log_delivery" {
  account_id                 = var.account_id
  storage_configuration_name = var.bucket_name
  bucket_name                = aws_s3_bucket.this.bucket

  depends_on = [aws_s3_bucket_policy.this]
}

resource "databricks_mws_log_delivery" "audit" {
  account_id               = var.account_id
  config_name              = "audit-logs"
  log_type                 = "AUDIT_LOGS"
  output_format            = "JSON"
  credentials_id           = databricks_mws_credentials.log_delivery.credentials_id
  storage_configuration_id = databricks_mws_storage_configurations.log_delivery.storage_configuration_id
  delivery_path_prefix     = var.prefix
}
