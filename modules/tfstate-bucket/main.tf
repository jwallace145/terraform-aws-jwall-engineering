resource "aws_s3_bucket" "this" {
  bucket = var.name

  tags = {
    Name      = var.name
    Component = var.component
  }

  # Hard-coded: lifecycle arguments cannot come from variables. Losing the
  # state bucket loses every stack's state, so the module never allows it.
  lifecycle {
    prevent_destroy = true
  }
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

locals {
  bucket_arn = aws_s3_bucket.this.arn

  hardened = length(var.prefix_access) > 0

  # Object-level actions a principal could use to read or change state.
  object_actions = [
    "s3:GetObject*",
    "s3:PutObject*",
    "s3:DeleteObject*",
    "s3:RestoreObject",
    "s3:AbortMultipartUpload",
    "s3:ListMultipartUploadParts",
  ]
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

  prefixes = sort(keys(var.prefix_access))
  writers  = distinct(flatten([for p in local.prefixes : var.prefix_access[p].write]))
  readers  = distinct(flatten([for p in local.prefixes : var.prefix_access[p].read]))
  listed   = distinct(concat(local.readers, local.writers))

  # Principals that read some prefix and write none. A principal that writes
  # any prefix is not covered; its IAM policy bounds where it writes.
  readers_only = [for a in local.readers : a if !contains(local.writers, a)]

  insecure_transport = {
    Sid       = "DenyInsecureTransport"
    Effect    = "Deny"
    Principal = "*"
    Action    = "s3:*"
    Resource = [
      local.bucket_arn,
      "${local.bucket_arn}/*",
    ]
    Condition = {
      Bool = {
        "aws:SecureTransport" = "false"
      }
    }
  }

  hardened_statements = concat(
    [
      {
        Sid       = "DenyUnlistedListing"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:ListBucket*"
        Resource  = local.bucket_arn
        Condition = {
          ArnNotEquals = {
            "aws:PrincipalArn" = distinct(concat(local.listed, var.admin_principal_arns))
          }
        }
      },
      {
        Sid         = "DenyObjectsOutsidePrefixes"
        Effect      = "Deny"
        Principal   = "*"
        Action      = local.object_actions
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
        Sid       = "DenyOutsidePrefix${i}"
        Effect    = "Deny"
        Principal = "*"
        Action    = local.object_actions
        Resource  = "${local.bucket_arn}/${p}*"
        Condition = {
          ArnNotEquals = {
            "aws:PrincipalArn" = distinct(concat(var.prefix_access[p].read, var.prefix_access[p].write, var.admin_principal_arns))
          }
        }
      }
    ],
    [
      for readers_only in [local.readers_only] : {
        Sid         = "DenyStateWritesByReaders"
        Effect      = "Deny"
        Principal   = "*"
        Action      = local.write_actions
        NotResource = [for p in local.prefixes : "${local.bucket_arn}/${p}*.tflock"]
        Condition = {
          ArnEquals = {
            "aws:PrincipalArn" = readers_only
          }
        }
      } if length(readers_only) > 0
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
    Version   = "2012-10-17"
    Statement = concat([local.insecure_transport], [for st in local.hardened_statements : st if local.hardened])
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = jsonencode(local.bucket_policy)

  # A bucket policy cannot be written while Block Public Access is still
  # being applied; order them explicitly.
  depends_on = [aws_s3_bucket_public_access_block.this]

  lifecycle {
    precondition {
      condition     = length(jsonencode(local.bucket_policy)) <= 20480
      error_message = "the bucket policy exceeds S3's 20 KB limit; use fewer prefix_access entries or principals."
    }
  }
}
