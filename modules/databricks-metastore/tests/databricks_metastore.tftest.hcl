mock_provider "databricks" {
  override_during = plan

  mock_resource "databricks_group" {
    defaults = {
      id = "1111"
    }
  }
}

variables {
  admin_user_names                 = ["owner@example.com", "second@example.com"]
  service_principal_application_id = "00000000-0000-0000-0000-000000000000"
}

run "metastore_has_no_storage_root" {
  command = plan

  assert {
    condition     = databricks_metastore.this.storage_root == null
    error_message = "the metastore must have no storage_root: storage lives in per-catalog locations"
  }

  assert {
    condition     = databricks_metastore.this.region == "us-east-1" && databricks_metastore.this.name == "jwall-engineering-us-east-1"
    error_message = "metastore must default to the shared us-east-1 name and region"
  }
}

run "metastore_owned_by_admin_group" {
  command = plan

  assert {
    condition     = databricks_metastore.this.owner == databricks_group.admins.display_name
    error_message = "metastore owner must be the admin group, not a person"
  }

  assert {
    condition     = databricks_group.admins.display_name == "jwall-engineering-metastore-admins"
    error_message = "admin group must use the default name"
  }
}

run "admins_include_service_principal" {
  command = plan

  assert {
    condition     = length(databricks_group_member.users) == 2 && contains(keys(databricks_group_member.users), "owner@example.com")
    error_message = "every admin user must be a member of the admin group"
  }

  assert {
    condition     = data.databricks_service_principal.automation.application_id == "00000000-0000-0000-0000-000000000000"
    error_message = "the service principal must be looked up by application_id"
  }

  assert {
    condition     = databricks_group_member.service_principal.group_id == "1111"
    error_message = "the service principal must be a member of the admin group"
  }
}

run "rejects_other_region" {
  command = plan

  variables {
    region = "eu-west-1"
  }

  expect_failures = [var.region]
}

run "rejects_non_email_user" {
  command = plan

  variables {
    admin_user_names = ["owner"]
  }

  expect_failures = [var.admin_user_names]
}
