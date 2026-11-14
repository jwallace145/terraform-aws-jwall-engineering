mock_provider "aws" {
  override_during = plan

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111122223333:role/jwall-engineering-databricks-poc-databricks-uc"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
    }
  }
}

mock_provider "databricks" {
  override_during = plan
}

mock_provider "time" {}

# For the apply run: values are generated once, at apply, so they stay
# consistent between plan and apply.
mock_provider "aws" {
  alias = "apply"

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
    }
  }
}

mock_provider "databricks" {
  alias = "apply"
}

# The external ID Databricks returns for the storage credential.
override_resource {
  target          = databricks_storage_credential.this
  override_during = apply
  values = {
    # Applied to each aws_iam_role block; role_arn stays as configured.
    aws_iam_role = {
      external_id           = "99999999-8888-7777-6666-555555555555"
      unity_catalog_iam_arn = "arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL"
    }
  }
}

# Realistic outputs of the provider's Unity Catalog helpers (databricks
# 1.142.0, captured by evaluating the data sources locally with these
# inputs), so the assertions below check what actually reaches IAM.
override_data {
  target          = data.databricks_aws_unity_catalog_assume_role_policy.uc
  override_during = apply
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"UnityCatalogAssumeRole\",\"Effect\":\"Allow\",\"Action\":\"sts:AssumeRole\",\"Principal\":{\"AWS\":\"arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL\"},\"Condition\":{\"StringEquals\":{\"sts:ExternalId\":\"99999999-8888-7777-6666-555555555555\"}}},{\"Sid\":\"ExplicitSelfRoleAssumption\",\"Effect\":\"Allow\",\"Action\":\"sts:AssumeRole\",\"Principal\":{\"AWS\":\"arn:aws:iam::111122223333:root\"},\"Condition\":{\"ArnLike\":{\"aws:PrincipalArn\":\"arn:aws:iam::111122223333:role/jwall-engineering-databricks-poc-databricks-uc\"},\"StringEquals\":{\"sts:ExternalId\":\"99999999-8888-7777-6666-555555555555\"}}}]}"
  }
}

override_data {
  target          = data.databricks_aws_unity_catalog_policy.uc
  override_during = plan
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:PutObject\",\"s3:DeleteObject\",\"s3:ListBucket\",\"s3:GetBucketLocation\",\"s3:ListBucketMultipartUploads\",\"s3:ListMultipartUploadParts\",\"s3:AbortMultipartUpload\"],\"Resource\":[\"arn:aws:s3:::jwall-engineering-databricks-poc-databricks-catalog/*\",\"arn:aws:s3:::jwall-engineering-databricks-poc-databricks-catalog\"]},{\"Effect\":\"Allow\",\"Action\":[\"sts:AssumeRole\"],\"Resource\":[\"arn:aws:iam::111122223333:role/jwall-engineering-databricks-poc-databricks-uc\"]}]}"
  }
}

variables {
  project              = "databricks-poc"
  workspace_id         = 1234567890123456
  admin_group_name     = "databricks-poc-workspace-admins"
  users_group_name     = "databricks-poc-workspace-users"
  apply_role_arn       = "arn:aws:iam::111122223333:role/ci-apply"
  management_role_arns = ["arn:aws:iam::111122223333:role/ci-plan", "arn:aws:iam::111122223333:role/admin"]
  tags = {
    Project = "databricks-poc"
    Owner   = "team-a"
  }
}

run "catalog_bucket_denies_non_uc_object_access" {
  command = plan


  assert {
    condition     = aws_s3_bucket.this.bucket == "jwall-engineering-databricks-poc-databricks-catalog"
    error_message = "the bucket must be <p>-databricks-catalog, the name the workspace's S3 endpoint policy admits"
  }

  assert {
    condition = (
      { for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid => s }["DenyObjectAccessExceptUC"].Effect == "Deny" &&
      { for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid => s }["DenyObjectAccessExceptUC"].Principal == "*" &&
      toset({ for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid => s }["DenyObjectAccessExceptUC"].Action) == toset(["s3:GetObject*", "s3:PutObject*"]) &&
      { for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid => s }["DenyObjectAccessExceptUC"].Resource == "arn:aws:s3:::jwall-engineering-databricks-poc-databricks-catalog/*" &&
      keys({ for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid => s }["DenyObjectAccessExceptUC"].Condition) == ["ArnNotEquals"] &&
      keys({ for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid => s }["DenyObjectAccessExceptUC"].Condition.ArnNotEquals) == ["aws:PrincipalArn"] &&
      flatten([{ for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid => s }["DenyObjectAccessExceptUC"].Condition.ArnNotEquals["aws:PrincipalArn"]]) == ["arn:aws:iam::111122223333:role/jwall-engineering-databricks-poc-databricks-uc"]
    )
    error_message = "Get/Put on every object must be denied to every principal whose aws:PrincipalArn is not exactly the Unity Catalog role (ArnNotEquals, UC role only)"
  }

  assert {
    condition = (
      { for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid => s }["DenyDeleteExceptUCAndApply"].Effect == "Deny" &&
      { for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid => s }["DenyDeleteExceptUCAndApply"].Principal == "*" &&
      { for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid => s }["DenyDeleteExceptUCAndApply"].Action == "s3:DeleteObject*" &&
      { for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid => s }["DenyDeleteExceptUCAndApply"].Resource == "arn:aws:s3:::jwall-engineering-databricks-poc-databricks-catalog/*" &&
      keys({ for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid => s }["DenyDeleteExceptUCAndApply"].Condition) == ["ArnNotEquals"] &&
      toset({ for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid => s }["DenyDeleteExceptUCAndApply"].Condition.ArnNotEquals["aws:PrincipalArn"]) == toset(["arn:aws:iam::111122223333:role/jwall-engineering-databricks-poc-databricks-uc", "arn:aws:iam::111122223333:role/ci-apply"])
    )
    error_message = "object deletes must be denied to every principal except the Unity Catalog role and the apply role"
  }

  assert {
    condition = (
      { for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid => s }["AllowApplyEmpty"].Effect == "Allow" &&
      { for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid => s }["AllowApplyEmpty"].Principal == { AWS = "arn:aws:iam::111122223333:role/ci-apply" } &&
      toset({ for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid => s }["AllowApplyEmpty"].Action) == toset(["s3:ListBucket", "s3:ListBucketVersions", "s3:DeleteObject", "s3:DeleteObjectVersion"]) &&
      toset({ for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid => s }["AllowApplyEmpty"].Resource) == toset(["arn:aws:s3:::jwall-engineering-databricks-poc-databricks-catalog", "arn:aws:s3:::jwall-engineering-databricks-poc-databricks-catalog/*"])
    )
    error_message = "the apply role must be allowed exactly list and delete, so destroy can empty the bucket"
  }

  assert {
    condition = alltrue([
      for sid, s in { for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid => s } : !strcontains(jsonencode(s), "arn:aws:iam::111122223333:role/ci-apply")
      if !contains(["DenyDeleteExceptUCAndApply", "AllowApplyEmpty"], sid)
    ]) && length({ for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid => s }) == 3
    error_message = "the apply role must appear only in the delete exemption and the list/delete allow, and the policy must have exactly the three statements"
  }

  # Terraform must keep managing the bucket's configuration and policy: only
  # object actions are denied.
  assert {
    condition = alltrue(flatten([
      for s in { for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Sid => s } : [
        for a in flatten([s.Action]) : startswith(a, "s3:GetObject") || startswith(a, "s3:PutObject") || startswith(a, "s3:DeleteObject")
      ] if s.Effect == "Deny"
    ]))
    error_message = "the denies must cover object actions only, never bucket configuration or policy actions"
  }
}

run "management_roles_have_no_object_rights" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : [
        for r in var.management_role_arns : !strcontains(jsonencode(s), r)
      ]
    ]))
    error_message = "management roles must get no statement: no allow and no exemption from the object denies"
  }
}

run "apply_role_cannot_read" {
  command = plan

  assert {
    condition = alltrue([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement :
      !anytrue([for a in flatten([s.Action]) : startswith(a, "s3:GetObject") || startswith(a, "s3:PutObject") || a == "s3:*"])
      if s.Effect == "Allow" && strcontains(jsonencode(try(s.Principal, "")), var.apply_role_arn)
    ])
    error_message = "no Allow statement for the apply role may contain s3:GetObject or s3:PutObject"
  }
}

run "bucket_private_and_encrypted" {
  command = plan

  assert {
    condition = (
      aws_s3_bucket.this.force_destroy == true &&
      aws_s3_bucket_public_access_block.this.block_public_acls &&
      aws_s3_bucket_public_access_block.this.block_public_policy &&
      aws_s3_bucket_public_access_block.this.ignore_public_acls &&
      aws_s3_bucket_public_access_block.this.restrict_public_buckets &&
      one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256" &&
      one(aws_s3_bucket_ownership_controls.this.rule).object_ownership == "BucketOwnerEnforced"
    )
    error_message = "the bucket must block public access, use SSE-S3, enforce bucket-owner ownership and be force_destroy"
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Name"] == "jwall-engineering-databricks-poc-databricks-catalog" && aws_s3_bucket.this.tags["Component"] == "databricks-catalog"
    error_message = "the bucket must carry Name and Component tags"
  }
}

run "uc_role_trust_self_assume_and_external_id" {
  # The trust helper reads after the credential exists (in a real plan too),
  # so its JSON is known only after an apply, here against the mocks.
  command = apply

  providers = {
    aws        = aws.apply
    databricks = databricks.apply
    time       = time
  }

  # Inputs to the helper: the role's own name and the credential's external ID.
  assert {
    condition = (
      data.databricks_aws_unity_catalog_assume_role_policy.uc.role_name == "jwall-engineering-databricks-poc-databricks-uc" &&
      data.databricks_aws_unity_catalog_assume_role_policy.uc.aws_account_id == "111122223333" &&
      data.databricks_aws_unity_catalog_assume_role_policy.uc.external_id == "99999999-8888-7777-6666-555555555555"
    )
    error_message = "the trust helper must be given the UC role's own name, the account and the storage credential's external ID"
  }

  assert {
    condition     = aws_iam_role.uc.name == "jwall-engineering-databricks-poc-databricks-uc"
    error_message = "the UC role must be <p>-databricks-uc, the name the workspace's S3 endpoint policy admits"
  }

  # What reaches IAM: the master role with the external ID, and the role itself.
  assert {
    condition = length([
      for s in jsondecode(aws_iam_role.uc.assume_role_policy).Statement : s
      if s.Effect == "Allow" && s.Action == "sts:AssumeRole" &&
      s.Principal.AWS == "arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL" &&
      s.Condition.StringEquals["sts:ExternalId"] == "99999999-8888-7777-6666-555555555555"
    ]) == 1
    error_message = "the trust must admit Databricks' Unity Catalog master role only with the credential's external ID"
  }

  assert {
    condition = length([
      for s in jsondecode(aws_iam_role.uc.assume_role_policy).Statement : s
      if s.Effect == "Allow" && s.Action == "sts:AssumeRole" &&
      try(s.Condition.ArnLike["aws:PrincipalArn"], s.Principal.AWS) == "arn:aws:iam::111122223333:role/jwall-engineering-databricks-poc-databricks-uc"
    ]) == 1
    error_message = "the trust must let the role assume itself (Databricks requires self-assuming storage credential roles)"
  }

  # The credential names the role by a built ARN (it cannot reference the
  # role: the role's trust needs the credential's external ID).
  assert {
    condition     = one(databricks_storage_credential.this.aws_iam_role).role_arn == "arn:aws:iam::111122223333:role/jwall-engineering-databricks-poc-databricks-uc"
    error_message = "the storage credential must point at the UC role's ARN"
  }

  assert {
    condition     = time_sleep.uc_role_propagation.create_duration == "30s"
    error_message = "the external location must wait 30s for the UC role to propagate"
  }
}

run "uc_role_permissions_scoped_to_bucket" {
  command = plan

  assert {
    condition = (
      data.databricks_aws_unity_catalog_policy.uc.bucket_name == "jwall-engineering-databricks-poc-databricks-catalog" &&
      data.databricks_aws_unity_catalog_policy.uc.role_name == "jwall-engineering-databricks-poc-databricks-uc" &&
      data.databricks_aws_unity_catalog_policy.uc.aws_account_id == "111122223333"
    )
    error_message = "the permissions helper must be scoped to the catalog bucket and the UC role"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.uc.policy).Statement :
      alltrue([for r in flatten([s.Resource]) : r != "*"])
    ]) && aws_iam_role_policy.uc.role == aws_iam_role.uc.id
    error_message = "the UC role's inline policy must come from the helper and name no Resource \"*\""
  }
}

run "catalog_is_isolated_and_bound" {
  command = plan

  assert {
    condition = (
      databricks_catalog.this.isolation_mode == "ISOLATED" &&
      databricks_external_location.this.isolation_mode == "ISOLATION_MODE_ISOLATED" &&
      databricks_storage_credential.this.isolation_mode == "ISOLATION_MODE_ISOLATED"
    )
    error_message = "the catalog, external location and storage credential must be isolated"
  }

  assert {
    condition = (
      databricks_workspace_binding.catalog.securable_type == "catalog" &&
      databricks_workspace_binding.catalog.securable_name == databricks_catalog.this.name &&
      databricks_workspace_binding.catalog.workspace_id == 1234567890123456 &&
      databricks_workspace_binding.external_location.securable_type == "external_location" &&
      databricks_workspace_binding.external_location.securable_name == databricks_external_location.this.name &&
      databricks_workspace_binding.external_location.workspace_id == 1234567890123456 &&
      databricks_workspace_binding.storage_credential.securable_type == "storage_credential" &&
      databricks_workspace_binding.storage_credential.securable_name == databricks_storage_credential.this.name &&
      databricks_workspace_binding.storage_credential.workspace_id == 1234567890123456
    )
    error_message = "the catalog, external location and storage credential must each be bound to workspace_id"
  }

  assert {
    condition     = databricks_catalog.this.owner == "databricks-poc-workspace-admins" && databricks_catalog.this.properties == var.tags
    error_message = "the catalog must be owned by the admin group and carry tags as properties"
  }
}

run "catalog_name_snake_case" {
  command = plan

  assert {
    condition     = databricks_catalog.this.name == "databricks_poc" && output.catalog_name == "databricks_poc"
    error_message = "databricks-poc must give the catalog databricks_poc"
  }
}

run "users_cannot_manage_catalog" {
  command = plan


  assert {
    condition = (
      !contains({ for g in databricks_grants.catalog.grant : g.principal => toset(g.privileges) }["databricks-poc-workspace-users"], "ALL_PRIVILEGES") &&
      !contains({ for g in databricks_grants.catalog.grant : g.principal => toset(g.privileges) }["databricks-poc-workspace-users"], "MANAGE") &&
      { for g in databricks_grants.catalog.grant : g.principal => toset(g.privileges) }["databricks-poc-workspace-users"] == toset(["USE_CATALOG", "USE_SCHEMA", "CREATE_SCHEMA", "CREATE_TABLE", "SELECT", "MODIFY"])
    )
    error_message = "users must get exactly USE_CATALOG, USE_SCHEMA, CREATE_SCHEMA, CREATE_TABLE, SELECT and MODIFY, never ALL_PRIVILEGES or MANAGE"
  }

  assert {
    condition     = { for g in databricks_grants.catalog.grant : g.principal => toset(g.privileges) }["databricks-poc-workspace-admins"] == toset(["ALL_PRIVILEGES"]) && length({ for g in databricks_grants.catalog.grant : g.principal => toset(g.privileges) }) == 2 && databricks_grants.catalog.catalog == databricks_catalog.this.name
    error_message = "the catalog grants must be ALL_PRIVILEGES for admins plus the users' grant, nothing else"
  }

  assert {
    condition     = { for g in databricks_grants.external_location.grant : g.principal => toset(g.privileges) } == { "databricks-poc-workspace-admins" = toset(["ALL_PRIVILEGES"]) } && databricks_grants.external_location.external_location == databricks_external_location.this.name
    error_message = "only admins may use the external location (ALL_PRIVILEGES)"
  }
}

run "external_location_under_managed_prefix" {
  command = plan

  assert {
    condition = (
      databricks_external_location.this.url == "s3://jwall-engineering-databricks-poc-databricks-catalog/managed/" &&
      databricks_catalog.this.storage_root == databricks_external_location.this.url &&
      databricks_external_location.this.credential_name == databricks_storage_credential.this.name
    )
    error_message = "the external location must be s3://<bucket>/managed/ with the storage credential, and the catalog's storage root"
  }
}

run "rejects_uc_role_as_management_role" {
  command = plan

  variables {
    management_role_arns = ["arn:aws:iam::111122223333:role/jwall-engineering-databricks-poc-databricks-uc"]
  }

  expect_failures = [aws_s3_bucket_policy.this]
}

run "rejects_bad_apply_role_arn" {
  command = plan

  variables {
    apply_role_arn = "ci-apply"
  }

  expect_failures = [var.apply_role_arn]
}

run "rejects_tags_without_owner" {
  command = plan

  variables {
    tags = { Project = "databricks-poc" }
  }

  expect_failures = [var.tags]
}
