# Managed storage for platform-owned catalogs (one per dataset producer): the
# metastore deliberately has no storage root (databricks-metastore), so every
# catalog needs a managed location. Nothing is ever written here: the catalogs
# hold only external volumes, consumers are bound read-only and granted no
# CREATE privilege. The bucket and role follow databricks-catalog's.

locals {
  bucket_arn = "arn:aws:s3:::${var.name}"

  # Built from the name, never from aws_iam_role.uc: the role's trust needs the
  # storage credential's external ID, so the credential cannot depend on it.
  uc_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.name}"

  # Each catalog's storage_root is a prefix under it: <url>/<catalog>.
  url = "s3://${var.name}/managed"

  tags = merge(var.tags, { Component = var.component })
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------- bucket

resource "aws_s3_bucket" "this" {
  bucket = var.name

  # It holds no data (see above), so a destroy never strands objects.
  force_destroy = true

  tags = merge(local.tags, { Name = var.name })
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Only the UC role may read or write objects; the apply role may list and
# delete, never read or put. Object actions only, so Terraform keeps managing
# the bucket's configuration and this policy.
resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyObjectAccessExceptUC"
        Effect    = "Deny"
        Principal = "*"
        Action    = ["s3:GetObject*", "s3:PutObject*"]
        Resource  = "${local.bucket_arn}/*"
        Condition = {
          ArnNotEquals = { "aws:PrincipalArn" = local.uc_role_arn }
        }
      },
      {
        Sid       = "DenyDeleteExceptUCAndApply"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:DeleteObject*"
        Resource  = "${local.bucket_arn}/*"
        Condition = {
          ArnNotEquals = { "aws:PrincipalArn" = [local.uc_role_arn, var.apply_role_arn] }
        }
      },
      {
        Sid       = "AllowApplyEmpty"
        Effect    = "Allow"
        Principal = { AWS = var.apply_role_arn }
        Action    = ["s3:ListBucket", "s3:ListBucketVersions", "s3:DeleteObject", "s3:DeleteObjectVersion"]
        Resource  = [local.bucket_arn, "${local.bucket_arn}/*"]
      },
    ]
  })

  lifecycle {
    precondition {
      condition     = var.apply_role_arn != local.uc_role_arn
      error_message = "apply_role_arn must not be the Unity Catalog role (${local.uc_role_arn}); pass the CI apply role."
    }
  }

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# ------------------------------------------------------ Unity Catalog role

# Databricks' documented order (as in databricks-catalog): the credential names
# the role by a built ARN, the role trusts Unity Catalog with the credential's
# external ID and itself, and the location waits for IAM.
resource "databricks_storage_credential" "this" {
  name           = var.name
  comment        = "Managed storage of the platform's dataset catalogs; managed by Terraform"
  isolation_mode = "ISOLATION_MODE_ISOLATED"
  owner          = var.owner_group_name

  # Destroy runs after the location is gone.
  force_destroy = true

  aws_iam_role {
    role_arn = local.uc_role_arn
  }
}

data "databricks_aws_unity_catalog_assume_role_policy" "uc" {
  aws_account_id = data.aws_caller_identity.current.account_id
  role_name      = var.name
  external_id    = databricks_storage_credential.this.aws_iam_role[0].external_id
}

data "databricks_aws_unity_catalog_policy" "uc" {
  aws_account_id = data.aws_caller_identity.current.account_id
  bucket_name    = var.name
  role_name      = var.name
}

resource "aws_iam_role" "uc" {
  name               = var.name
  assume_role_policy = data.databricks_aws_unity_catalog_assume_role_policy.uc.json

  tags = merge(local.tags, { Name = var.name })
}

resource "aws_iam_role_policy" "uc" {
  name   = "unity-catalog-managed-storage"
  role   = aws_iam_role.uc.id
  policy = data.databricks_aws_unity_catalog_policy.uc.json
}

resource "time_sleep" "uc_role_propagation" {
  create_duration = "30s"

  depends_on = [aws_iam_role.uc, aws_iam_role_policy.uc, aws_s3_bucket_policy.this]
}

# --------------------------------------------------------------- location

resource "databricks_external_location" "this" {
  name            = var.name
  url             = local.url
  credential_name = databricks_storage_credential.this.name
  owner           = var.owner_group_name
  comment         = "Managed storage of the platform's dataset catalogs (a prefix per catalog); managed by Terraform"
  isolation_mode  = "ISOLATION_MODE_ISOLATED"

  # Destroy runs after the catalogs are gone.
  force_destroy = true

  depends_on = [time_sleep.uc_role_propagation]
}

resource "databricks_workspace_binding" "location" {
  workspace_id   = var.host_workspace_id
  securable_type = "external_location"
  securable_name = databricks_external_location.this.name
}

resource "databricks_workspace_binding" "credential" {
  workspace_id   = var.host_workspace_id
  securable_type = "storage_credential"
  securable_name = databricks_storage_credential.this.name
}

# Authoritative: a grant made by hand on the location is removed.
resource "databricks_grants" "location" {
  external_location = databricks_external_location.this.name

  grant {
    principal  = var.owner_group_name
    privileges = ["ALL_PRIVILEGES"]
  }
}
