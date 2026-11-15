# Applied through the shared-objects host: the workspace-level provider's
# host is databricks-host-workspace's workspace_url. Authentication comes from
# the environment (DATABRICKS_CLIENT_ID, DATABRICKS_CLIENT_SECRET).
provider "aws" {
  region = "us-east-1"
}

provider "databricks" {
  host = "https://dbc-01234567-89ab.cloud.databricks.com"
}

module "nnue" {
  source = "../../"

  name   = "rusty-chess-nnue"
  bucket = "jwall-engineering-rusty-chess-nnue"
  prefix = "data/"

  host_workspace_id = 1111111111111111
  owner_group_name  = "jwall-engineering-metastore-admins"

  consumers = {
    braveheart = { workspace_id = 2222222222222222, users_group_name = "braveheart-workspace-users" }
  }
}

output "endpoint_dataset" {
  value = module.nnue.endpoint_dataset
}
