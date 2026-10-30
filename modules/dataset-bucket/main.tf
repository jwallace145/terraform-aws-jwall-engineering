# A durable, append-only dataset: training data that every later model is
# built and compared from. Objects are write-once by convention (new runs get
# new keys), so the bucket is not versioned: versioning would only store an
# accidental re-upload twice. Nothing expires. Data moves to
# Intelligent-Tiering, because it is read in bursts and then goes cold.

locals {
  arn         = "arn:aws:s3:::${var.name}"
  objects_arn = "${local.arn}/${var.prefix}*"
  list_prefix = { StringLike = { "s3:prefix" = "${var.prefix}*" } }
}

resource "aws_s3_bucket" "this" {
  bucket = var.name

  tags = {
    Name      = var.name
    Component = "dataset"
    Purpose   = "dataset"
  }

  # Hard-coded: lifecycle arguments cannot come from variables. The data is
  # kept; the bucket is never destroyed with the rest of a stack.
  lifecycle {
    prevent_destroy = true
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

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Writers upload in S3 Standard (the AWS CLI's default); this moves them.
  # S3 does not transition objects under 128 KB, such as manifests.
  rule {
    id     = "intelligent-tiering"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = var.transition_days
      storage_class = "INTELLIGENT_TIERING"
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

locals {
  reader_statements = [for statement in [
    {
      Sid       = "ReadDatasetObjects"
      Effect    = "Allow"
      Principal = { AWS = var.reader_role_arns }
      Action    = "s3:GetObject"
      Resource  = local.objects_arn
    },
    {
      Sid       = "ListDatasetForReaders"
      Effect    = "Allow"
      Principal = { AWS = var.reader_role_arns }
      Action    = "s3:ListBucket"
      Resource  = local.arn
      Condition = local.list_prefix
    },
  ] : statement if length(var.reader_role_arns) > 0]

  bucket_policy = {
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.arn, "${local.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ], local.reader_statements)
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = jsonencode(local.bucket_policy)

  # A bucket policy cannot be written while Block Public Access is still
  # being applied; order them explicitly.
  depends_on = [aws_s3_bucket_public_access_block.this]
}

# Writers only add: no GetObject (a writer may run untrusted code and has no
# need to read the data back) and no DeleteObject.
resource "aws_iam_role_policy" "writer" {
  for_each = toset(var.writer_role_names)

  name = "${var.name}-write"
  role = each.value

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Multipart uploads (the CLI uses them above 8 MB) are authorized by
        # PutObject; AbortMultipartUpload lets the CLI clean up its own
        # failed upload. Neither removes a completed object.
        Sid      = "AddDatasetObjects"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:AbortMultipartUpload"]
        Resource = local.objects_arn
      },
      {
        Sid       = "ListDatasetPrefix"
        Effect    = "Allow"
        Action    = "s3:ListBucket"
        Resource  = local.arn
        Condition = local.list_prefix
      },
    ]
  })
}
