# Who may read one onboarded dataset (the data-access reconcile, one instance
# per dataset with a location). Per agreed consumer, its workspace is bound to
# the dataset's location and storage credential, and its users group holds
# USE SCHEMA and READ VOLUME on the dataset's schema and its `files` volume
# (databricks-dataset). Consumers read through the volume only: the location
# grants READ FILES to the owner group alone. Every grant set is authoritative
# and always holds the owner group, so it is never empty and a grant made by
# hand (BROWSE included) is removed at the next apply.

# The location's grants were `databricks_grants.this[0]` (READ FILES for each
# consumer) before volumes: updated in place, never destroyed and recreated.
moved {
  from = databricks_grants.this[0]
  to   = databricks_grants.location
}

locals {
  consumer_groups = { for k, c in var.consumers : k => c.users_group_name }
}

resource "databricks_grants" "location" {
  external_location = var.external_location_name

  grant {
    principal  = var.owner_group_name
    privileges = ["READ_FILES"]
  }
}

resource "databricks_grants" "schema" {
  count = var.schema_full_name != null ? 1 : 0

  schema = var.schema_full_name

  grant {
    principal  = var.owner_group_name
    privileges = ["USE_SCHEMA"]
  }

  dynamic "grant" {
    for_each = local.consumer_groups
    content {
      principal  = grant.value
      privileges = ["USE_SCHEMA"]
    }
  }
}

resource "databricks_grants" "volume" {
  count = var.volume_full_name != null ? 1 : 0

  volume = var.volume_full_name

  grant {
    principal  = var.owner_group_name
    privileges = ["READ_VOLUME"]
  }

  dynamic "grant" {
    for_each = local.consumer_groups
    content {
      principal  = grant.value
      privileges = ["READ_VOLUME"]
    }
  }
}

# The credential is bound to consumer workspaces below, so its grant set is
# authoritative too: a grant made by hand on it (READ FILES, say) would
# otherwise work from those workspaces and survive every sweep.
resource "databricks_grants" "credential" {
  storage_credential = var.storage_credential_name

  grant {
    principal  = var.owner_group_name
    privileges = ["READ_FILES"]
  }
}

# Binding a consumer's workspace is what lets it use the isolated location and
# credential at all. Depending on every grant set makes Terraform create each
# binding last and destroy it first, so a run that stops half way leaves less
# access, never more.
resource "databricks_workspace_binding" "consumer" {
  for_each = var.consumers

  workspace_id   = each.value.workspace_id
  securable_type = "external_location"
  securable_name = var.external_location_name

  depends_on = [databricks_grants.location, databricks_grants.credential, databricks_grants.schema, databricks_grants.volume]
}

resource "databricks_workspace_binding" "credential" {
  for_each = var.consumers

  workspace_id   = each.value.workspace_id
  securable_type = "storage_credential"
  securable_name = var.storage_credential_name

  depends_on = [databricks_grants.location, databricks_grants.credential, databricks_grants.schema, databricks_grants.volume]
}
