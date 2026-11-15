mock_provider "aws" {
  override_during = plan

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111122223333:role/jwall-engineering-rusty-chess-nnue-databricks-share"
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

variables {
  name              = "rusty-chess-nnue"
  bucket            = "jwall-engineering-rusty-chess-nnue"
  prefix            = "data/"
  host_workspace_id = 1111111111111111
  owner_group_name  = "jwall-engineering-metastore-admins"
  consumers = {
    braveheart = { workspace_id = 2222222222222222, users_group_name = "braveheart-workspace-users" }
    team-a     = { workspace_id = 3333333333333333, users_group_name = "team-a-workspace-users" }
  }
}

run "one_read_only_location_for_every_consumer" {
  command = plan

  assert {
    condition = (
      databricks_external_location.this.name == "jwall-engineering-rusty-chess-nnue" &&
      databricks_external_location.this.url == "s3://jwall-engineering-rusty-chess-nnue/data" &&
      databricks_external_location.this.read_only == true &&
      databricks_external_location.this.skip_validation == true &&
      databricks_external_location.this.isolation_mode == "ISOLATION_MODE_ISOLATED" &&
      databricks_external_location.this.credential_name == databricks_storage_credential.this.name &&
      databricks_external_location.this.owner == "jwall-engineering-metastore-admins"
    )
    error_message = "the dataset must get one isolated, read-only location at s3://<bucket>/<prefix> (no trailing slash), owned by the metastore admins"
  }

  assert {
    condition = (
      length(databricks_workspace_binding.this) == 3 &&
      toset([for b in databricks_workspace_binding.this : b.workspace_id]) == toset([1111111111111111, 2222222222222222, 3333333333333333]) &&
      alltrue([for b in databricks_workspace_binding.this : b.securable_type == "external_location" && b.securable_name == databricks_external_location.this.name])
    )
    error_message = "the one location must be bound to the host and to every consumer"
  }

  assert {
    condition = (
      databricks_grants.this[0].external_location == databricks_external_location.this.name &&
      { for g in databricks_grants.this[0].grant : g.principal => toset(g.privileges) } == {
        "braveheart-workspace-users" = toset(["READ_FILES"])
        "team-a-workspace-users"     = toset(["READ_FILES"])
      }
    )
    error_message = "every consumer's users group, and nobody else, must get exactly READ_FILES"
  }
}

run "credential_read_only_and_host_only" {
  command = plan

  assert {
    condition = (
      databricks_storage_credential.this.name == "jwall-engineering-rusty-chess-nnue-databricks-share" &&
      databricks_storage_credential.this.read_only == true &&
      databricks_storage_credential.this.isolation_mode == "ISOLATION_MODE_ISOLATED" &&
      databricks_storage_credential.this.owner == "jwall-engineering-metastore-admins" &&
      one(databricks_storage_credential.this.aws_iam_role).role_arn == "arn:aws:iam::111122223333:role/jwall-engineering-rusty-chess-nnue-databricks-share"
    )
    error_message = "the credential must be read-only, isolated, owned by the metastore admins and point at the share role"
  }

  assert {
    condition     = databricks_workspace_binding.credential.workspace_id == 1111111111111111 && databricks_workspace_binding.credential.securable_type == "storage_credential"
    error_message = "the credential must be bound to the host only: consumers read through the location"
  }
}

run "role_gets_no_reads_of_its_own" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_role_policy.this.policy).Statement == [
      {
        Sid      = "LocateBucket"
        Effect   = "Allow"
        Action   = "s3:GetBucketLocation"
        Resource = "arn:aws:s3:::jwall-engineering-rusty-chess-nnue"
      },
      {
        Sid      = "SelfAssume"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = "arn:aws:iam::111122223333:role/jwall-engineering-rusty-chess-nnue-databricks-share"
      },
    ]
    error_message = "the role's own policy may hold only GetBucketLocation and its self-assume: reads come from the producer's bucket policy"
  }

  assert {
    condition = (
      aws_iam_role.this.name == "jwall-engineering-rusty-chess-nnue-databricks-share" &&
      data.databricks_aws_unity_catalog_assume_role_policy.this.role_name == "jwall-engineering-rusty-chess-nnue-databricks-share" &&
      data.databricks_aws_unity_catalog_assume_role_policy.this.aws_account_id == "111122223333"
    )
    error_message = "the role's trust must come from the Unity Catalog helper for this role"
  }
}

run "endpoint_dataset_matches_the_role" {
  command = plan

  assert {
    condition = output.endpoint_dataset == {
      bucket   = "jwall-engineering-rusty-chess-nnue"
      prefix   = "data/"
      role_arn = "arn:aws:iam::111122223333:role/jwall-engineering-rusty-chess-nnue-databricks-share"
    }
    error_message = "endpoint_dataset must give consumers the bucket, prefix and the share role's ARN"
  }
}

run "no_consumers_keeps_the_host_binding" {
  command = plan

  variables {
    consumers = {}
  }

  assert {
    condition     = length(databricks_workspace_binding.this) == 1 && databricks_workspace_binding.this["host"].workspace_id == 1111111111111111 && length(databricks_grants.this) == 0
    error_message = "with no consumers, only the host is bound and nobody is granted"
  }
}

run "rejects_host_as_consumer_key" {
  command = plan

  variables {
    consumers = { host = { workspace_id = 2222222222222222, users_group_name = "x-workspace-users" } }
  }

  expect_failures = [var.consumers]
}

run "rejects_long_name" {
  command = plan

  variables {
    name = "a-very-long-dataset-name-indeed-x"
  }

  expect_failures = [var.name]
}

run "rejects_prefix_with_leading_slash" {
  command = plan

  variables {
    prefix = "/data/"
  }

  expect_failures = [var.prefix]
}
