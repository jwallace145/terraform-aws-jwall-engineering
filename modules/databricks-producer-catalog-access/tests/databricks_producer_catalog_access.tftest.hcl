# Who may use one producer catalog: per consumer with an agreed edge into any
# of the producer's datasets, a read-only binding of the catalog to its
# workspace and USE CATALOG for its users group, in an authoritative grant set
# that always holds the owner group. Each dataset inside is granted on its own
# (databricks-dataset-access).

mock_provider "databricks" {
  override_during = plan
}

variables {
  catalog_name     = "braveheart_selfplay"
  owner_group_name = "jwall-engineering-metastore-admins"
  consumers = {
    braveheart-databricks = { workspace_id = 2222222222222222, users_group_name = "braveheart-databricks-workspace-users" }
    team-a                = { workspace_id = 3333333333333333, users_group_name = "team-a-workspace-users" }
  }
}

run "consumers_are_bound_read_only_and_may_use_the_catalog" {
  command = plan

  assert {
    condition = (databricks_grants.catalog.catalog == var.catalog_name
      && jsonencode(sort([for g in databricks_grants.catalog.grant : g.principal])) == jsonencode(["braveheart-databricks-workspace-users", "jwall-engineering-metastore-admins", "team-a-workspace-users"])
    && alltrue([for g in databricks_grants.catalog.grant : g.privileges == toset(["USE_CATALOG"])]))
    error_message = "USE_CATALOG, and nothing else (never BROWSE), for the owner group and each consumer's users group"
  }

  assert {
    condition = (length(databricks_workspace_binding.consumer) == 2
      && alltrue([for b in databricks_workspace_binding.consumer : b.securable_type == "catalog" && b.securable_name == var.catalog_name && b.binding_type == "BINDING_TYPE_READ_ONLY"])
    && toset([for b in databricks_workspace_binding.consumer : b.workspace_id]) == toset([2222222222222222, 3333333333333333]))
    error_message = "each consumer workspace is bound to the catalog, read-only"
  }

  assert {
    # tolist: a list(string) output never equals a tuple literal with `==`.
    condition     = output.consumers == tolist(["braveheart-databricks", "team-a"])
    error_message = "consumers lists the bound projects, sorted"
  }
}

run "without_consumers_only_the_owner_holds_a_grant" {
  command = plan

  variables {
    consumers = {}
  }

  # Revoking the last consumer's last edge into the producer unbinds the
  # catalog and leaves the owner group alone in its grant set.
  assert {
    condition = (length(databricks_workspace_binding.consumer) == 0
    && jsonencode([for g in databricks_grants.catalog.grant : g.principal]) == jsonencode(["jwall-engineering-metastore-admins"]))
    error_message = "with no consumer, nothing is bound and only the owner group holds a grant"
  }
}

run "a_consumer_without_a_users_group_is_refused" {
  command = plan

  variables {
    consumers = {
      braveheart-databricks = { workspace_id = 2222222222222222, users_group_name = " " }
    }
  }

  expect_failures = [var.consumers]
}

run "a_catalog_name_that_is_not_a_unity_catalog_name_is_refused" {
  command = plan

  variables {
    catalog_name = "Braveheart-Selfplay"
  }

  expect_failures = [var.catalog_name]
}
