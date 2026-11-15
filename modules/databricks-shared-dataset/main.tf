locals {
  # One role, credential and location per dataset, wherever it is consumed.
  role_name = "${var.name_root}-${var.name}-databricks-share"
  # Built from the name, never from aws_iam_role.this: the role's trust needs
  # the storage credential's external ID, so the credential cannot depend on it.
  role_arn   = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.role_name}"
  bucket_arn = "arn:aws:s3:::${var.bucket}"

  location_name = "${var.name_root}-${var.name}"
  # No trailing slash: Databricks stores the URL without one.
  url = "s3://${var.bucket}/${trimsuffix(var.prefix, "/")}"

  # The host keeps its binding (an isolated securable is bound to the
  # workspace it was created from); every consumer gets one.
  bound_workspace_ids = merge(
    { "host" = var.host_workspace_id },
    { for k, c in var.consumers : k => c.workspace_id },
  )

  tags = {
    Component = var.component
  }
}

data "aws_caller_identity" "current" {}

# ------------------------------------------------------------------ role

# The order Databricks documents for a storage credential, as in
# databricks-catalog: the credential names the role by a built ARN, the
# role's trust comes from the credential's external ID.
resource "databricks_storage_credential" "this" {
  name           = local.role_name
  comment        = "Shared dataset ${var.name} (${local.url}), read-only; managed by Terraform"
  isolation_mode = "ISOLATION_MODE_ISOLATED"
  read_only      = true
  owner          = var.owner_group_name

  force_destroy = true

  aws_iam_role {
    role_arn = local.role_arn
  }
}

data "databricks_aws_unity_catalog_assume_role_policy" "this" {
  aws_account_id = data.aws_caller_identity.current.account_id
  role_name      = local.role_name
  external_id    = databricks_storage_credential.this.aws_iam_role[0].external_id
}

resource "aws_iam_role" "this" {
  name               = local.role_name
  assume_role_policy = data.databricks_aws_unity_catalog_assume_role_policy.this.json

  tags = merge(local.tags, { Name = local.role_name })
}

# Deliberately no read or list: in the same account the dataset's bucket
# policy naming this role (its readers) allows them on its own, so the
# project that owns the data grants access and can revoke it.
# GetBucketLocation reveals no data and Databricks needs it; the self
# AssumeRole is Databricks' requirement for storage credential roles (the
# trust admits the account root on condition of this role's ARN, so the
# role's own policy must allow it too).
resource "aws_iam_role_policy" "this" {
  name = "shared-dataset-locate"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "LocateBucket"
        Effect   = "Allow"
        Action   = "s3:GetBucketLocation"
        Resource = local.bucket_arn
      },
      {
        Sid      = "SelfAssume"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = local.role_arn
      },
    ]
  })
}

resource "time_sleep" "role_propagation" {
  create_duration = "30s"

  depends_on = [aws_iam_role.this, aws_iam_role_policy.this]
}

# -------------------------------------------------------------- location

# Validation is skipped: it checks the role can read and list, which only the
# producer's bucket policy allows, and that lives in another stack applied on
# its own schedule. Until the producer names the role as a reader, reads fail
# with access denied and nothing else changes.
resource "databricks_external_location" "this" {
  name            = local.location_name
  url             = local.url
  credential_name = databricks_storage_credential.this.name
  read_only       = true
  skip_validation = true
  owner           = var.owner_group_name
  comment         = "Shared dataset ${var.name}, read-only for ${join(", ", sort(keys(var.consumers)))}; managed by Terraform"
  isolation_mode  = "ISOLATION_MODE_ISOLATED"

  # Drops the location and what is registered on it, never the dataset's
  # objects (the location is read-only).
  force_destroy = true

  depends_on = [time_sleep.role_propagation]
}

resource "databricks_workspace_binding" "this" {
  for_each = local.bound_workspace_ids

  workspace_id   = each.value
  securable_type = "external_location"
  securable_name = databricks_external_location.this.name
}

resource "databricks_workspace_binding" "credential" {
  workspace_id   = var.host_workspace_id
  securable_type = "storage_credential"
  securable_name = databricks_storage_credential.this.name
}

# Consumers read files, nothing more; read_only refuses writes whatever the
# grant. The owner (the metastore admin group) keeps every privilege.
resource "databricks_grants" "this" {
  # The provider needs at least one grant block.
  count = length(var.consumers) > 0 ? 1 : 0

  external_location = databricks_external_location.this.name

  dynamic "grant" {
    for_each = { for k, c in var.consumers : k => c.users_group_name }
    content {
      principal  = grant.value
      privileges = ["READ_FILES"]
    }
  }
}
