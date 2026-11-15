mock_provider "databricks" {
  override_during = plan

  mock_data "databricks_group" {
    defaults = {
      id = "2222"
    }
  }

  mock_resource "databricks_mws_workspaces" {
    defaults = {
      workspace_id = 1234567890123456
    }
  }
}

variables {
  account_id       = "11111111-2222-3333-4444-555555555555"
  metastore_id     = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  admin_group_name = "jwall-engineering-metastore-admins"
  tags = {
    Project     = "shared"
    Environment = "prod"
    CostCenter  = "platform"
    Workspace   = "jwall-engineering-shared"
    Owner       = "owner"
    ManagedBy   = "terraform"
  }
}

run "serverless_with_no_customer_infrastructure" {
  command = plan

  assert {
    condition = (
      databricks_mws_workspaces.this.compute_mode == "SERVERLESS" &&
      databricks_mws_workspaces.this.network_id == null &&
      databricks_mws_workspaces.this.credentials_id == null &&
      databricks_mws_workspaces.this.storage_configuration_id == null
    )
    error_message = "the host must be serverless with no network, cross-account credential or storage configuration (no VPC, NAT or root bucket)"
  }

  assert {
    condition     = databricks_mws_workspaces.this.workspace_name == "jwall-engineering-shared" && databricks_mws_workspaces.this.aws_region == "us-east-1" && databricks_mws_workspaces.this.custom_tags == var.tags
    error_message = "the host must default to jwall-engineering-shared in us-east-1 with the tags"
  }
}

run "assigned_to_the_metastore" {
  command = plan

  assert {
    condition     = databricks_metastore_assignment.this.metastore_id == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" && databricks_metastore_assignment.this.workspace_id == 1234567890123456
    error_message = "the host must be assigned to the metastore"
  }
}

run "only_the_metastore_admins" {
  command = plan

  assert {
    condition = (
      data.databricks_group.admins.display_name == "jwall-engineering-metastore-admins" &&
      databricks_mws_permission_assignment.admins.principal_id == tonumber(data.databricks_group.admins.id) &&
      toset(databricks_mws_permission_assignment.admins.permissions) == toset(["ADMIN"])
    )
    error_message = "the metastore admin group must be the host's only assignment, as ADMIN"
  }
}

run "rejects_reserved_tag" {
  command = plan

  variables {
    tags = {
      Project     = "shared"
      Environment = "prod"
      CostCenter  = "platform"
      Workspace   = "jwall-engineering-shared"
      Owner       = "owner"
      ManagedBy   = "terraform"
      Vendor      = "x"
    }
  }

  expect_failures = [var.tags]
}

run "rejects_other_region" {
  command = plan

  variables {
    region = "us-west-2"
  }

  expect_failures = [var.region]
}
