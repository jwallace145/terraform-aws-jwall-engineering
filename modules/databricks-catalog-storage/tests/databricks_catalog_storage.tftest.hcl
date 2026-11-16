# The platform catalogs' managed storage: one bucket, Unity Catalog role,
# storage credential and external location, all named var.name, bound to the
# shared host only. Mock providers: nothing is called.

mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

mock_provider "databricks" {
  override_during = plan

  mock_data "databricks_aws_unity_catalog_assume_role_policy" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "databricks_aws_unity_catalog_policy" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

mock_provider "time" {}

variables {
  name              = "jwall-engineering-dataset-catalogs"
  host_workspace_id = 1111111111111111
  owner_group_name  = "jwall-engineering-metastore-admins"
  apply_role_arn    = "arn:aws:iam::123456789012:role/jwall-engineering-infra-ci-apply"
}

run "everything_takes_the_name" {
  command = plan

  assert {
    condition = (aws_s3_bucket.this.bucket == var.name && aws_iam_role.uc.name == var.name
      && databricks_storage_credential.this.name == var.name && databricks_external_location.this.name == var.name
      && output.url == "s3://jwall-engineering-dataset-catalogs/managed"
    && databricks_external_location.this.url == output.url)
    error_message = "the bucket, role, credential and location are all named var.name, and the location is s3://<name>/managed"
  }
}

run "only_the_uc_role_reads_or_writes" {
  command = plan

  assert {
    condition = one([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s.Condition.ArnNotEquals["aws:PrincipalArn"]
      if s.Sid == "DenyObjectAccessExceptUC"
    ]) == output.uc_role_arn
    error_message = "the bucket policy denies object reads and writes to everyone but the Unity Catalog role"
  }
}

run "bound_to_the_host_only_and_owned_by_the_admin_group" {
  command = plan

  assert {
    condition = (databricks_workspace_binding.location.workspace_id == var.host_workspace_id
      && databricks_workspace_binding.credential.workspace_id == var.host_workspace_id
      && databricks_storage_credential.this.isolation_mode == "ISOLATION_MODE_ISOLATED"
      && databricks_external_location.this.isolation_mode == "ISOLATION_MODE_ISOLATED"
      && databricks_storage_credential.this.owner == var.owner_group_name
    && databricks_external_location.this.owner == var.owner_group_name)
    error_message = "the credential and location are isolated, owned by the admin group, and bound to the host only"
  }
}

run "a_name_that_is_not_kebab_case_is_refused" {
  command = plan

  variables {
    name = "Dataset_Catalogs"
  }

  expect_failures = [var.name]
}
