mock_provider "aws" {
  override_during = plan

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/jwall-engineering-ds-braveheart-selfplay-positions"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

mock_provider "databricks" {
  override_during = plan
}

mock_provider "time" {}

variables {
  name              = "jwall-engineering-ds-braveheart-selfplay-positions"
  bucket            = "jwall-engineering-braveheart-selfplay-positions"
  prefix            = "data/"
  host_workspace_id = 1111111111111111
  owner_group_name  = "jwall-engineering-metastore-admins"
}

run "onboarding_is_read_only_bound_to_the_host_and_grants_nothing" {
  command = plan

  assert {
    condition = (databricks_external_location.this.name == var.name
      && databricks_external_location.this.url == "s3://jwall-engineering-braveheart-selfplay-positions/data"
      && databricks_external_location.this.read_only && databricks_external_location.this.skip_validation
      && databricks_external_location.this.isolation_mode == "ISOLATION_MODE_ISOLATED"
    && databricks_storage_credential.this.read_only && databricks_storage_credential.this.name == var.name)
    error_message = "one read-only, isolated credential and location, named var.name"
  }

  assert {
    condition = (databricks_workspace_binding.location.workspace_id == 1111111111111111
    && databricks_workspace_binding.credential.workspace_id == 1111111111111111)
    error_message = "bound to the shared host only"
  }

  assert {
    condition     = [for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s.Action] == ["s3:GetBucketLocation", "sts:AssumeRole"]
    error_message = "the role reads nothing of its own: the producer's bucket policy grants reads"
  }

  assert {
    condition     = output.endpoint_dataset == { bucket = var.bucket, prefix = var.prefix, role_arn = "arn:aws:iam::123456789012:role/${var.name}" }
    error_message = "endpoint_dataset names the role by ARN, known before it exists"
  }
}

run "a_prefix_without_its_trailing_slash_is_refused" {
  command = plan

  variables {
    prefix = "data"
  }

  expect_failures = [var.prefix]
}
