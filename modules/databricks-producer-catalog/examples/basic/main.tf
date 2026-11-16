# Applied through the shared-objects host: the workspace-level provider's
# host is databricks-host-workspace's workspace_url.
provider "databricks" {
  host = "https://dbc-01234567-89ab.cloud.databricks.com"
}

module "braveheart_selfplay" {
  source = "../../"

  producer          = "braveheart-selfplay"
  storage_url       = "s3://jwall-engineering-dataset-catalogs/managed"
  host_workspace_id = 1111111111111111
  owner_group_name  = "jwall-engineering-metastore-admins"
}

output "catalog_name" {
  value = module.braveheart_selfplay.catalog_name
}
