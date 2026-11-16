# Who may read one onboarded dataset. Per consumer: its workspace is bound to
# the dataset's external location and storage credential, and its users group
# holds USE SCHEMA and READ VOLUME on the dataset's schema and volume. The
# location grants READ FILES to the owner group only: the volume is the one
# way in. Every grant set is authoritative and always holds the owner group,
# so it is never empty and a grant made by hand is removed.

mock_provider "databricks" {
  override_during = plan
}

variables {
  external_location_name  = "jwall-engineering-ds-braveheart-selfplay-positions"
  storage_credential_name = "jwall-engineering-ds-braveheart-selfplay-positions"
  owner_group_name        = "jwall-engineering-metastore-admins"
  schema_full_name        = "braveheart_selfplay.positions"
  volume_full_name        = "braveheart_selfplay.positions.files"
  consumers = {
    braveheart-databricks = { workspace_id = 2222222222222222, users_group_name = "braveheart-databricks-workspace-users" }
    team-a                = { workspace_id = 3333333333333333, users_group_name = "team-a-workspace-users" }
  }
}

run "two_consumers" {
  command = plan

  assert {
    condition = (databricks_grants.location.external_location == var.external_location_name
      && jsonencode(sort([for g in databricks_grants.location.grant : g.principal])) == jsonencode(["jwall-engineering-metastore-admins"])
    && alltrue([for g in databricks_grants.location.grant : g.privileges == toset(["READ_FILES"])]))
    error_message = "the location grants READ_FILES to the owner group only: consumers read through the volume"
  }

  assert {
    condition = (databricks_grants.schema[0].schema == var.schema_full_name
      && jsonencode(sort([for g in databricks_grants.schema[0].grant : g.principal])) == jsonencode(["braveheart-databricks-workspace-users", "jwall-engineering-metastore-admins", "team-a-workspace-users"])
    && alltrue([for g in databricks_grants.schema[0].grant : g.privileges == toset(["USE_SCHEMA"])]))
    error_message = "USE_SCHEMA, and nothing else, for the owner group and each consumer's users group"
  }

  assert {
    condition = (databricks_grants.volume[0].volume == var.volume_full_name
      && jsonencode(sort([for g in databricks_grants.volume[0].grant : g.principal])) == jsonencode(["braveheart-databricks-workspace-users", "jwall-engineering-metastore-admins", "team-a-workspace-users"])
    && alltrue([for g in databricks_grants.volume[0].grant : g.privileges == toset(["READ_VOLUME"])]))
    error_message = "READ_VOLUME, and nothing else, for the owner group and each consumer's users group"
  }

  assert {
    condition = (length(databricks_workspace_binding.consumer) == 2 && length(databricks_workspace_binding.credential) == 2
      && alltrue([for b in databricks_workspace_binding.consumer : b.securable_type == "external_location" && b.securable_name == var.external_location_name])
      && alltrue([for b in databricks_workspace_binding.credential : b.securable_type == "storage_credential" && b.securable_name == var.storage_credential_name])
      && toset([for b in databricks_workspace_binding.consumer : b.workspace_id]) == toset([2222222222222222, 3333333333333333])
    && toset([for b in databricks_workspace_binding.credential : b.workspace_id]) == toset([2222222222222222, 3333333333333333]))
    error_message = "each consumer workspace is bound to the location and to the credential"
  }

  assert {
    # tolist: a list(string) output never equals a tuple literal with `==`.
    condition     = output.consumers == tolist(["braveheart-databricks", "team-a"])
    error_message = "consumers lists the bound projects, sorted"
  }
}

run "the_credential_grants_nothing_to_consumers" {
  command = plan

  # The credential is bound to consumer workspaces, so its grant set must be
  # authoritative too: a grant made by hand on it would otherwise work there.
  assert {
    condition = (databricks_grants.credential.storage_credential == var.storage_credential_name
      && jsonencode([for g in databricks_grants.credential.grant : g.principal]) == jsonencode(["jwall-engineering-metastore-admins"])
    && alltrue([for g in databricks_grants.credential.grant : g.privileges == toset(["READ_FILES"])]))
    error_message = "the storage credential's grants are authoritative and hold the owner group alone"
  }
}

run "no_consumers" {
  command = plan

  variables {
    consumers = {}
  }

  # Revoking the last consumer leaves each grant set with the owner group
  # alone, rather than unmanaged, and removes every binding.
  assert {
    condition = (length(databricks_workspace_binding.consumer) == 0 && length(databricks_workspace_binding.credential) == 0
      && jsonencode([for g in databricks_grants.location.grant : g.principal]) == jsonencode(["jwall-engineering-metastore-admins"])
      && jsonencode([for g in databricks_grants.schema[0].grant : g.principal]) == jsonencode(["jwall-engineering-metastore-admins"])
    && jsonencode([for g in databricks_grants.volume[0].grant : g.principal]) == jsonencode(["jwall-engineering-metastore-admins"]))
    error_message = "with no consumer, every grant set holds only the owner group and nothing is bound"
  }
}

run "without_a_volume_only_the_location_is_managed" {
  command = plan

  variables {
    schema_full_name = null
    volume_full_name = null
  }

  assert {
    condition     = length(databricks_grants.schema) == 0 && length(databricks_grants.volume) == 0 && length(databricks_workspace_binding.consumer) == 2
    error_message = "without a schema and volume, only the location's grants and the bindings are managed"
  }
}

run "a_volume_without_a_schema_is_refused" {
  command = plan

  variables {
    schema_full_name = null
  }

  expect_failures = [var.volume_full_name]
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
