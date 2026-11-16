mock_provider "databricks" {
  override_during = plan
}

variables {
  external_location_name = "jwall-engineering-ds-braveheart-selfplay-positions"
  consumers = {
    braveheart-databricks = { workspace_id = 2222222222222222, users_group_name = "braveheart-databricks-workspace-users" }
    team-a                = { workspace_id = 3333333333333333, users_group_name = "team-a-workspace-users" }
  }
}

run "two_consumers" {
  command = plan

  assert {
    condition = (length(databricks_workspace_binding.consumer) == 2
      && alltrue([for b in databricks_workspace_binding.consumer : b.securable_name == var.external_location_name && b.securable_type == "external_location"])
    && toset([for b in databricks_workspace_binding.consumer : b.workspace_id]) == toset([2222222222222222, 3333333333333333]))
    error_message = "one binding of the location per consumer workspace"
  }

  assert {
    condition = (length(databricks_grants.this) == 1
      && databricks_grants.this[0].external_location == var.external_location_name
      && alltrue([for g in databricks_grants.this[0].grant : g.privileges == toset(["READ_FILES"])])
    && toset([for g in databricks_grants.this[0].grant : g.principal]) == toset(["braveheart-databricks-workspace-users", "team-a-workspace-users"]))
    error_message = "READ_FILES, and nothing else, for each consumer's users group"
  }

  assert {
    # tolist: a list(string) output never equals a tuple literal with `==`.
    condition     = output.consumers == tolist(["braveheart-databricks", "team-a"])
    error_message = "consumers lists the bound projects, sorted"
  }
}

run "no_consumers" {
  command = plan

  variables {
    consumers = {}
  }

  assert {
    condition     = length(databricks_workspace_binding.consumer) == 0 && length(databricks_grants.this) == 0
    error_message = "a dataset nobody has agreed to share gets no binding and no grant"
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
