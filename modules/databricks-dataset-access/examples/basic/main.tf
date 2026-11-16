# Applied through the shared-objects host, like databricks-dataset: the
# workspace-level provider's host is databricks-host-workspace's workspace_url.
# Authentication comes from the environment.
provider "databricks" {
  host = "https://dbc-01234567-89ab.cloud.databricks.com"
}

module "positions_access" {
  source = "../../"

  external_location_name  = "jwall-engineering-ds-braveheart-selfplay-positions"
  storage_credential_name = "jwall-engineering-ds-braveheart-selfplay-positions"
  owner_group_name        = "jwall-engineering-metastore-admins"
  schema_full_name        = "braveheart_selfplay.positions"
  volume_full_name        = "braveheart_selfplay.positions.files"

  consumers = {
    braveheart-databricks = { workspace_id = 2222222222222222, users_group_name = "braveheart-databricks-workspace-users" }
  }
}

output "consumers" {
  value = module.positions_access.consumers
}
