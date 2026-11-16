# One isolated catalog per dataset producer, owned by the platform, with its
# managed location under the shared catalog storage, bound read-write to the
# host only (consumers are bound read-only by databricks-producer-catalog-access).

mock_provider "databricks" {
  override_during = plan
}

variables {
  producer          = "braveheart-selfplay"
  storage_url       = "s3://jwall-engineering-dataset-catalogs/managed"
  host_workspace_id = 1111111111111111
  owner_group_name  = "jwall-engineering-metastore-admins"
}

run "the_catalog_is_named_for_the_producer" {
  command = plan

  assert {
    condition = (output.catalog_name == "braveheart_selfplay" && databricks_catalog.this.name == "braveheart_selfplay"
      && databricks_catalog.this.storage_root == "s3://jwall-engineering-dataset-catalogs/managed/braveheart_selfplay"
    && databricks_catalog.this.properties["producer"] == "braveheart-selfplay")
    error_message = "the catalog is the producer with - replaced by _, its storage under <storage_url>/<catalog>, and it records the producer"
  }
}

run "isolated_and_owned_by_the_admin_group" {
  command = plan

  assert {
    condition     = databricks_catalog.this.isolation_mode == "ISOLATED" && databricks_catalog.this.owner == var.owner_group_name
    error_message = "the catalog is isolated and owned by the admin group, never by a producer or consumer"
  }
}

run "bound_read_write_to_the_host_only" {
  command = plan

  assert {
    condition = (databricks_workspace_binding.host.workspace_id == var.host_workspace_id
      && databricks_workspace_binding.host.securable_type == "catalog"
      && databricks_workspace_binding.host.securable_name == "braveheart_selfplay"
    && databricks_workspace_binding.host.binding_type == "BINDING_TYPE_READ_WRITE")
    error_message = "the catalog is bound read-write to the host, through which the platform manages it"
  }
}

run "a_producer_that_is_not_kebab_case_is_refused" {
  command = plan

  variables {
    producer = "Braveheart_Selfplay"
  }

  expect_failures = [var.producer]
}

run "a_storage_url_that_is_not_s3_is_refused" {
  command = plan

  variables {
    storage_url = "https://example.com/managed"
  }

  expect_failures = [var.storage_url]
}
