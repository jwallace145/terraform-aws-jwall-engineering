# A durable, append-only dataset: training data that every later model is
# built and compared from. Objects are write-once by convention (new runs get
# new keys), so by default the bucket is not versioned: versioning would only
# store an accidental re-upload twice. By default nothing expires. Data moves
# to Intelligent-Tiering, because it is read in bursts and then goes cold.
# Versioning and expiry of named sub-prefixes are opt-in, for projects that
# keep scratch data next to the dataset.

locals {
  arn         = "arn:aws:s3:::${var.name}"
  objects_arn = "${local.arn}/${var.prefix}*"
  list_prefix = { StringLike = { "s3:prefix" = "${var.prefix}*" } }

  write_once_arns = {
    for role, g in var.role_grants : role => [for p in g.write_once : "${local.arn}/${var.prefix}${p}*"]
  }
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

resource "aws_s3_bucket_versioning" "this" {
  count = var.versioning ? 1 : 0

  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # The provider recommends enabling versioning first: a failed versioning
  # call must not leave live expiry rules on an unversioned bucket.
  depends_on = [aws_s3_bucket_versioning.this]

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

  # Only the sub-prefixes named in expire_prefixes ever expire.
  dynamic "rule" {
    for_each = var.expire_prefixes

    content {
      id     = "expire-${replace(rule.key, "/", "-")}"
      status = "Enabled"

      filter {
        prefix = "${var.prefix}${rule.key}"
      }

      expiration {
        days = rule.value
      }
    }
  }

  dynamic "rule" {
    for_each = var.expire_noncurrent_days == null ? [] : [var.expire_noncurrent_days]

    content {
      id     = "expire-noncurrent-versions"
      status = "Enabled"

      filter {
        prefix = ""
      }

      noncurrent_version_expiration {
        noncurrent_days = rule.value
      }
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

# Narrower grants, for a role that reads one part of the dataset and adds to
# another (a trainer reads positions and writes nets). Never delete.
resource "aws_iam_role_policy" "grant" {
  for_each = var.role_grants

  name = "${var.name}-access"
  role = each.key

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      length(each.value.read) == 0 ? [] : [{
        Sid      = "ReadDatasetObjects"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = [for p in each.value.read : "${local.arn}/${var.prefix}${p}*"]
      }],
      length(each.value.write) == 0 ? [] : [{
        Sid      = "AddDatasetObjects"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:AbortMultipartUpload"]
        Resource = [for p in each.value.write : "${local.arn}/${var.prefix}${p}*"]
      }],
      [{
        Sid      = "ListDatasetPrefixes"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = local.arn
        Condition = {
          StringLike = {
            "s3:prefix" = [for p in distinct(concat(each.value.read, each.value.write, each.value.write_once)) : "${var.prefix}${p}*"]
          }
        }
      }],
      # Add-only. The conditional PutObject creates an object only if the key
      # is absent; later multipart parts are not creating requests, so they are
      # allowed unconditionally, but completing the upload is the creating
      # request and carries the condition. No unconditional PutObject here.
      [for s in [
        {
          Sid       = "AddDatasetObjectsIfAbsent"
          Effect    = "Allow"
          Action    = "s3:PutObject"
          Resource  = local.write_once_arns[each.key]
          Condition = { StringEquals = { "s3:if-none-match" = "*" } }
        },
        {
          Sid       = "AddDatasetObjectParts"
          Effect    = "Allow"
          Action    = "s3:PutObject"
          Resource  = local.write_once_arns[each.key]
          Condition = { Bool = { "s3:ObjectCreationOperation" = "false" } }
        },
        {
          Sid      = "AbortDatasetUploads"
          Effect   = "Allow"
          Action   = "s3:AbortMultipartUpload"
          Resource = local.write_once_arns[each.key]
        },
      ] : s if length(each.value.write_once) > 0],
    )
  })
}
