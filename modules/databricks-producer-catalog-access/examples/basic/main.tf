# Applied through the shared-objects host: the workspace-level provider's
# host is databricks-host-workspace's workspace_url.
provider "databricks" {
  host = "https://dbc-01234567-89ab.cloud.databricks.com"
}

module "braveheart_selfplay_access" {
  source = "../../"

  catalog_name     = "braveheart_selfplay"
  owner_group_name = "jwall-engineering-metastore-admins"

  consumers = {
    braveheart-databricks = { workspace_id = 2222222222222222, users_group_name = "braveheart-databricks-workspace-users" }
  }
}

output "consumers" {
  value = module.braveheart_selfplay_access.consumers
}
