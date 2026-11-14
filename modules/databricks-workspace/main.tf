locals {
  # <p> in the naming standard, for example jwall-engineering-databricks-poc.
  prefix = "${var.name_root}-${var.project}"

  root_bucket_name   = "${local.prefix}-databricks-root"
  cross_account_name = "${local.prefix}-databricks-cross-account"
  security_group     = "${local.prefix}-databricks-workspace"

  # Outbound TCP to 0.0.0.0/0 that Databricks requires of a customer-managed
  # VPC's security group, from
  # https://docs.databricks.com/aws/en/security/network/classic/customer-managed-vpc
  # (checked 2026-11-13). 8443-8451 is one range: 8443 and 8445 are control
  # plane API calls, 8444 Unity Catalog lineage and logging, 8446-8451
  # reserved by Databricks for future use.
  egress_ports = [
    { from = 443, to = 443, description = "Databricks infrastructure, cloud data sources and library repositories" },
    { from = 3306, to = 3306, description = "Legacy Hive metastore" },
    { from = 53, to = 53, description = "DNS resolution when a custom DNS is used" },
    { from = 6666, to = 6666, description = "Secure cluster connectivity (PrivateLink)" },
    { from = 2443, to = 2443, description = "FIPS encryption (compliance security profile)" },
    { from = 5432, to = 5432, description = "Classic compute to Lakebase" },
    { from = 8443, to = 8451, description = "Control plane API, Unity Catalog lineage and logging, reserved" },
  ]

  catalog_bucket_name = "${local.prefix}-databricks-catalog"
  uc_role_arn         = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.prefix}-databricks-uc"

  # Databricks-owned buckets the classic compute plane reads in us-east-1:
  # artifacts, logs, system tables storage and the sample datasets, from
  # https://docs.databricks.com/aws/en/resources/ip-domain-region
  # ("Addresses for artifact storage, log storage, system tables, and shared
  # datasets buckets", checked 2026-11-13).
  databricks_buckets = [
    "databricks-prod-artifacts-${data.aws_region.current.name}",
    "databricks-prod-storage-virginia",
    "system-tables-prod-${data.aws_region.current.name}-uc-metastore-bucket",
    "databricks-datasets-virginia",
  ]

  tags = {
    Component = var.component
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# ---------------------------------------------------------------- network

data "aws_subnet" "this" {
  # Keyed by position, not by ID: with subnets created in the same stack the
  # IDs are unknown at plan, and for_each keys must be known.
  for_each = { for i, id in var.subnet_ids : tostring(i) => id }

  id = each.value

  lifecycle {
    # Databricks rejects workspace subnets outside /17-/26. vpc stays
    # generic, so the check lives here, for subnets from any source.
    postcondition {
      condition     = tonumber(split("/", self.cidr_block)[1]) >= 17 && tonumber(split("/", self.cidr_block)[1]) <= 26
      error_message = "subnet ${self.id} is ${self.cidr_block}: Databricks needs each workspace subnet's netmask between /17 and /26; pass other subnets in subnet_ids."
    }

    postcondition {
      condition     = self.vpc_id == var.vpc_id
      error_message = "subnet ${self.id} is in ${self.vpc_id}, not vpc_id (${var.vpc_id}); every entry of subnet_ids must be a subnet of vpc_id."
    }
  }
}

resource "aws_security_group" "this" {
  name        = local.security_group
  description = "Databricks workspace clusters: all traffic within the group, documented ports out"
  vpc_id      = var.vpc_id

  ingress {
    description = "All traffic from the workspace clusters (same group)"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    self        = true
  }

  egress {
    description = "All traffic to the workspace clusters (same group)"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    self        = true
  }

  dynamic "egress" {
    for_each = local.egress_ports

    content {
      description = egress.value.description
      protocol    = "tcp"
      from_port   = egress.value.from
      to_port     = egress.value.to
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tags = merge(local.tags, { Name = local.security_group })
}

resource "databricks_mws_networks" "this" {
  account_id         = var.account_id
  network_name       = "${local.prefix}-databricks-network"
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids
  security_group_ids = [aws_security_group.this.id]

  # Fail at the subnet check, not inside the Databricks API.
  depends_on = [data.aws_subnet.this]
}

# ------------------------------------------------------------ root bucket

resource "aws_s3_bucket" "root" {
  bucket = local.root_bucket_name

  # Workspace root storage (DBFS root, system data) is disposable with the
  # workspace: tearing a workspace down must not need a manual emptying.
  force_destroy = true

  tags = merge(local.tags, { Name = local.root_bucket_name })
}

resource "aws_s3_bucket_public_access_block" "root" {
  bucket = aws_s3_bucket.root.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "root" {
  bucket = aws_s3_bucket.root.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_ownership_controls" "root" {
  bucket = aws_s3_bucket.root.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Databricks' documented root bucket policy. With databricks_e2_account_id
# it only admits Databricks principals tagged with this account's ID. The
# helper is evaluated locally, so it takes the name rather than the bucket
# resource and is known at plan time.
data "databricks_aws_bucket_policy" "root" {
  bucket                   = local.root_bucket_name
  databricks_e2_account_id = var.account_id
}

resource "aws_s3_bucket_policy" "root" {
  bucket = aws_s3_bucket.root.id
  policy = data.databricks_aws_bucket_policy.root.json

  depends_on = [aws_s3_bucket_public_access_block.root]
}

resource "databricks_mws_storage_configurations" "this" {
  account_id                 = var.account_id
  storage_configuration_name = local.root_bucket_name
  bucket_name                = aws_s3_bucket.root.bucket

  depends_on = [aws_s3_bucket_policy.root]
}

# ------------------------------------------------------ cross-account role

data "databricks_aws_assume_role_policy" "this" {
  external_id = var.account_id
}

# "customer": the permissions Databricks documents for a customer-managed
# VPC (no VPC, subnet, gateway or route creation).
data "databricks_aws_crossaccount_policy" "this" {
  policy_type = "customer"
}

resource "aws_iam_role" "cross_account" {
  name               = local.cross_account_name
  assume_role_policy = data.databricks_aws_assume_role_policy.this.json

  tags = merge(local.tags, { Name = local.cross_account_name })
}

resource "aws_iam_role_policy" "cross_account" {
  name   = "databricks-customer-vpc"
  role   = aws_iam_role.cross_account.id
  policy = data.databricks_aws_crossaccount_policy.this.json
}

# IAM is eventually consistent and Databricks validates the role when the
# credentials are created.
resource "time_sleep" "iam_propagation" {
  create_duration = "20s"

  depends_on = [aws_iam_role_policy.cross_account]
}

resource "databricks_mws_credentials" "this" {
  credentials_name = local.cross_account_name
  role_arn         = aws_iam_role.cross_account.arn

  depends_on = [time_sleep.iam_propagation]
}

# --------------------------------------------------------------- workspace

resource "databricks_mws_workspaces" "this" {
  account_id      = var.account_id
  workspace_name  = "${var.project}-${var.environment}"
  deployment_name = var.deployment_name
  aws_region      = "us-east-1"
  pricing_tier    = "PREMIUM"

  credentials_id           = databricks_mws_credentials.this.credentials_id
  storage_configuration_id = databricks_mws_storage_configurations.this.storage_configuration_id
  network_id               = databricks_mws_networks.this.network_id

  custom_tags = var.tags
}

resource "databricks_metastore_assignment" "this" {
  workspace_id = databricks_mws_workspaces.this.workspace_id
  metastore_id = var.metastore_id
}

# ------------------------------------------------------------------ access

resource "databricks_group" "admins" {
  display_name = "${var.project}-workspace-admins"
}

resource "databricks_group" "users" {
  display_name = "${var.project}-workspace-users"
}

data "databricks_user" "admins" {
  for_each = toset(var.admin_user_names)

  user_name = each.value
}

data "databricks_user" "users" {
  for_each = toset(var.user_names)

  user_name = each.value
}

resource "databricks_group_member" "admins" {
  for_each = data.databricks_user.admins

  group_id  = databricks_group.admins.id
  member_id = each.value.id
}

resource "databricks_group_member" "users" {
  for_each = data.databricks_user.users

  group_id  = databricks_group.users.id
  member_id = each.value.id
}

data "databricks_service_principal" "automation" {
  application_id = var.service_principal_application_id
}

resource "databricks_group_member" "service_principal" {
  group_id  = databricks_group.admins.id
  member_id = data.databricks_service_principal.automation.sp_id
}

# Account groups reach a workspace only once it has identity federation,
# which the metastore assignment turns on.
resource "databricks_mws_permission_assignment" "admins" {
  workspace_id = databricks_mws_workspaces.this.workspace_id
  principal_id = tonumber(databricks_group.admins.id)
  permissions  = ["ADMIN"]

  depends_on = [databricks_metastore_assignment.this]
}

resource "databricks_mws_permission_assignment" "users" {
  workspace_id = databricks_mws_workspaces.this.workspace_id
  principal_id = tonumber(databricks_group.users.id)
  permissions  = ["USER"]

  depends_on = [databricks_metastore_assignment.this]
}

# ----------------------------------------------------- S3 endpoint policy

# For vpc's s3_gateway_endpoint.policy. It depends on names only, never on
# resources: the endpoint is created before this module (and before the
# Unity Catalog role), so the role is named in a condition, which AWS does not
# validate, never in Principal, which it does. Anything not listed here is
# denied at the endpoint.
locals {
  s3_endpoint_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DatabricksRequired"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:*"
        Resource = flatten([
          for b in local.databricks_buckets : ["arn:aws:s3:::${b}", "arn:aws:s3:::${b}/*"]
        ])
      },
      {
        # The root bucket's own policy is the real guard here.
        Sid       = "WorkspaceRoot"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:*"
        Resource  = ["arn:aws:s3:::${local.root_bucket_name}", "arn:aws:s3:::${local.root_bucket_name}/*"]
      },
      {
        Sid       = "UnityCatalogOnly"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:*"
        Resource  = ["arn:aws:s3:::${local.catalog_bucket_name}", "arn:aws:s3:::${local.catalog_bucket_name}/*"]
        Condition = {
          ArnEquals = { "aws:PrincipalArn" = local.uc_role_arn }
        }
      },
    ]
  })
}
