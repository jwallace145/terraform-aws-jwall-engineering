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

# In its producer's catalog: a schema holding one external volume, `files`, at
# the location's URL, so consumers find the dataset in Catalog Explorer.

run "with_a_catalog_a_schema_and_an_external_volume_at_the_url" {
  command = plan

  variables {
    catalog_name = "braveheart_selfplay"
    schema_name  = "positions"
  }

  assert {
    condition = (databricks_schema.this[0].catalog_name == "braveheart_selfplay" && databricks_schema.this[0].name == "positions"
      && databricks_schema.this[0].owner == var.owner_group_name
      && databricks_volume.files[0].name == "files" && databricks_volume.files[0].volume_type == "EXTERNAL"
      && databricks_volume.files[0].catalog_name == "braveheart_selfplay" && databricks_volume.files[0].schema_name == "positions"
      && databricks_volume.files[0].storage_location == output.url
    && databricks_volume.files[0].owner == var.owner_group_name)
    error_message = "the dataset is a schema in the producer's catalog with an external volume files at the location's URL, both owned by the admin group"
  }

  assert {
    condition = (output.schema_full_name == "braveheart_selfplay.positions"
      && output.volume_full_name == "braveheart_selfplay.positions.files"
    && output.volume_path == "/Volumes/braveheart_selfplay/positions/files")
    error_message = "the outputs name the schema, the volume and the path consumers read"
  }
}

run "without_a_catalog_nothing_is_added" {
  command = plan

  assert {
    condition = (length(databricks_schema.this) == 0 && length(databricks_volume.files) == 0
    && output.schema_full_name == null && output.volume_full_name == null && output.volume_path == null)
    error_message = "without a catalog the dataset is onboarded as a location only"
  }
}

run "a_schema_without_a_catalog_is_refused" {
  command = plan

  variables {
    schema_name = "positions"
  }

  expect_failures = [var.schema_name]
}
