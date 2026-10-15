data "aws_caller_identity" "current" {}

locals {
  component   = "site-bucket"
  bucket_name = "jwall-engineering-${var.project}"
}

resource "aws_s3_bucket" "this" {
  bucket = local.bucket_name

  tags = {
    Component = local.component
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

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Lifecycle rules require versioning to exist first.
  depends_on = [aws_s3_bucket_versioning.this]

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "expire-previews"
    status = "Enabled"

    filter {
      prefix = "previews/"
    }

    expiration {
      days = 14
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Policies are built with jsonencode() rather than aws_iam_policy_document so
# that their content is known at plan time and checkable with mocked providers.
locals {
  bucket_arn = aws_s3_bucket.this.arn

  hardened = length(var.prefix_writers) > 0
  prefixes = sort(keys(var.prefix_writers))

  write_actions = [
    "s3:PutObject*",
    "s3:DeleteObject*",
    "s3:RestoreObject",
    "s3:AbortMultipartUpload",
  ]

  # Bucket configuration, including the bucket policy itself. Without this,
  # any principal with s3:* could replace the policy and undo the rest.
  configuration_actions = [
    "s3:PutBucket*",
    "s3:DeleteBucket*",
    "s3:PutAccelerateConfiguration",
    "s3:PutAnalyticsConfiguration",
    "s3:PutEncryptionConfiguration",
    "s3:PutIntelligentTieringConfiguration",
    "s3:PutInventoryConfiguration",
    "s3:PutLifecycleConfiguration",
    "s3:PutMetricsConfiguration",
    "s3:PutReplicationConfiguration",
  ]

  # Writes only: the content is public through CloudFront, so reads stay
  # governed by IAM alone.
  hardened_statements = concat(
    [
      {
        Sid         = "DenyWritesOutsidePrefixes"
        Effect      = "Deny"
        Principal   = "*"
        Action      = local.write_actions
        NotResource = [for p in local.prefixes : "${local.bucket_arn}/${p}*"]
        Condition = {
          ArnNotEquals = {
            "aws:PrincipalArn" = var.admin_principal_arns
          }
        }
      },
    ],
    [
      for i, p in local.prefixes : {
        Sid       = "DenyWritesToPrefix${i}"
        Effect    = "Deny"
        Principal = "*"
        Action    = local.write_actions
        Resource  = "${local.bucket_arn}/${p}*"
        Condition = {
          ArnNotEquals = {
            "aws:PrincipalArn" = distinct(concat(var.prefix_writers[p], var.admin_principal_arns))
          }
        }
      }
    ],
    [
      {
        Sid       = "DenyUnmanagedConfiguration"
        Effect    = "Deny"
        Principal = "*"
        Action    = local.configuration_actions
        Resource  = local.bucket_arn
        Condition = {
          ArnNotEquals = {
            "aws:PrincipalArn" = var.admin_principal_arns
          }
        }
      },
    ],
  )

  bucket_policy = {
    Version = "2012-10-17"
    Statement = concat([
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
      {
        Sid    = "AllowCloudFrontServicePrincipalRead"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.this.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
    ], [for st in local.hardened_statements : st if local.hardened])
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = jsonencode(local.bucket_policy)

  depends_on = [aws_s3_bucket_public_access_block.this]

  lifecycle {
    precondition {
      condition     = length(jsonencode(local.bucket_policy)) <= 20480
      error_message = "the bucket policy exceeds S3's 20 KB limit; use fewer prefix_writers entries or principals."
    }
  }
}
