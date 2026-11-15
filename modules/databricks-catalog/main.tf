locals {
  # <p> in the naming standard, for example jwall-engineering-databricks-poc.
  # Both names must equal what databricks-workspace's S3 endpoint policy
  # admits: the endpoint lets requests to this bucket through only when
  # aws:PrincipalArn is this role.
  prefix       = "${var.name_root}-${var.project}"
  bucket_name  = "${local.prefix}-databricks-catalog"
  bucket_arn   = "arn:aws:s3:::${local.bucket_name}"
  uc_role_name = "${local.prefix}-databricks-uc"

  # Built from the name, never from aws_iam_role.uc: the role's trust needs the
  # storage credential's external ID, so the credential cannot depend on it.
  uc_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.uc_role_name}"

  catalog_name = replace(var.project, "-", "_")

  tags = {
    Component = var.component
  }
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------- catalog bucket

resource "aws_s3_bucket" "this" {
  bucket = local.bucket_name

  # Unity Catalog managed storage is disposable with the project. The CLI
  # empties the bucket with the apply role before terraform destroy, while
  # AllowApplyEmpty still stands. This is only a backstop: it runs after the
  # bucket policy is destroyed, so it relies on the apply role's IAM identity
  # policy (the databricks/manage CI policy leaf grants list/delete here).
  force_destroy = true

  tags = merge(local.tags, { Name = local.bucket_name })
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
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Only the UC role may read or write objects, and every other principal is
# denied them, whatever its IAM policies allow. The apply role may list and
# delete, never read or put: the CLI empties the bucket with it before
# terraform destroy, while this policy still stands. Only object actions are
# denied, so Terraform keeps managing the bucket's configuration and this
# policy. This is not absolute: a principal that can rewrite this policy or
# the UC role's trust (the apply role, account admins) can open the data, and
# is trusted not to; the plan role cannot.
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
    # The UC role is the only principal the denies exempt for reads; passing
    # it as a management or apply role would be a mistake in the stack.
    precondition {
      condition     = !contains(concat(var.management_role_arns, [var.apply_role_arn]), local.uc_role_arn)
      error_message = "management_role_arns and apply_role_arn must not contain the Unity Catalog role (${local.uc_role_arn}); pass the CI plan, apply and admin roles only."
    }
  }

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# -------------------------------------------------------- Unity Catalog role

# Databricks' documented order for an AWS storage credential
# (https://docs.databricks.com/aws/en/connect/unity-catalog/cloud-storage/s3/s3-external-location-manual,
# checked 2026-11-13): create the credential with the role's ARN, take its
# external ID, then give the role a trust policy that admits Databricks'
# Unity Catalog master role with that external ID and the role itself
# (Databricks blocks storage credentials whose role is not self-assuming).
# Terraform does it in one apply: the credential names the role by a built
# ARN, the role's trust is built from the credential's external ID, and the
# external location (which validates the credential) waits for IAM.
resource "databricks_storage_credential" "this" {
  name           = local.uc_role_name
  comment        = "Unity Catalog managed storage of ${local.catalog_name}; managed by Terraform"
  isolation_mode = "ISOLATION_MODE_ISOLATED"

  # Destroy runs after the catalog and external location are gone.
  force_destroy = true

  aws_iam_role {
    role_arn = local.uc_role_arn
  }
}

data "databricks_aws_unity_catalog_assume_role_policy" "uc" {
  aws_account_id = data.aws_caller_identity.current.account_id
  role_name      = local.uc_role_name
  external_id    = databricks_storage_credential.this.aws_iam_role[0].external_id
}

data "databricks_aws_unity_catalog_policy" "uc" {
  aws_account_id = data.aws_caller_identity.current.account_id
  bucket_name    = local.bucket_name
  role_name      = local.uc_role_name
}

resource "aws_iam_role" "uc" {
  name               = local.uc_role_name
  assume_role_policy = data.databricks_aws_unity_catalog_assume_role_policy.uc.json

  tags = merge(local.tags, { Name = local.uc_role_name })
}

resource "aws_iam_role_policy" "uc" {
  name   = "unity-catalog-managed-storage"
  role   = aws_iam_role.uc.id
  policy = data.databricks_aws_unity_catalog_policy.uc.json
}

# IAM is eventually consistent; the external location validates the
# credential against the role.
resource "time_sleep" "uc_role_propagation" {
  create_duration = "30s"

  depends_on = [aws_iam_role.uc, aws_iam_role_policy.uc, aws_s3_bucket_policy.this]
}

# --------------------------------------------------------------- catalog

resource "databricks_external_location" "this" {
  name = local.bucket_name
  # No trailing slash: Databricks stores the URL without one, and the
  # catalog's storage_root is taken from it, so a slash here makes the provider
  # report an inconsistent final plan for the catalog.
  url             = "s3://${local.bucket_name}/managed"
  credential_name = databricks_storage_credential.this.name
  comment         = "Unity Catalog managed storage of ${local.catalog_name}; managed by Terraform"
  isolation_mode  = "ISOLATION_MODE_ISOLATED"

  # Unity Catalog keeps dropped managed tables for a while; they must not
  # block destroy once the catalog is gone.
  force_destroy = true

  depends_on = [time_sleep.uc_role_propagation]
}

resource "databricks_catalog" "this" {
  name           = local.catalog_name
  comment        = "Catalog of ${var.project}; managed by Terraform"
  storage_root   = databricks_external_location.this.url
  isolation_mode = "ISOLATED"
  owner          = var.admin_group_name
  properties     = var.tags

  # Destroy drops the catalog with its schemas and tables; Unity Catalog's
  # delayed cleanup is not waited for (the bucket is emptied directly).
  force_destroy = true
}

# Isolated securables are bound to the workspace that created them; these
# make the binding explicit and keep it if it is removed elsewhere.
resource "databricks_workspace_binding" "catalog" {
  workspace_id   = var.workspace_id
  securable_type = "catalog"
  securable_name = databricks_catalog.this.name
}

resource "databricks_workspace_binding" "external_location" {
  workspace_id   = var.workspace_id
  securable_type = "external_location"
  securable_name = databricks_external_location.this.name
}

resource "databricks_workspace_binding" "storage_credential" {
  workspace_id   = var.workspace_id
  securable_type = "storage_credential"
  securable_name = databricks_storage_credential.this.name
}

# --------------------------------------------------------------- grants

resource "databricks_grants" "catalog" {
  catalog = databricks_catalog.this.name

  grant {
    principal  = var.admin_group_name
    privileges = ["ALL_PRIVILEGES"]
  }

  grant {
    principal  = var.users_group_name
    privileges = ["USE_CATALOG", "USE_SCHEMA", "CREATE_SCHEMA", "CREATE_TABLE", "SELECT", "MODIFY"]
  }
}

resource "databricks_grants" "external_location" {
  external_location = databricks_external_location.this.name

  grant {
    principal  = var.admin_group_name
    privileges = ["ALL_PRIVILEGES"]
  }
}
