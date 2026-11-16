# Applied through the shared-objects host: the workspace-level provider's
# host is databricks-host-workspace's workspace_url. Authentication comes from
# the environment (DATABRICKS_CLIENT_ID, DATABRICKS_CLIENT_SECRET).
provider "aws" {
  region = "us-east-1"
}

provider "databricks" {
  host = "https://dbc-01234567-89ab.cloud.databricks.com"
}

module "dataset_catalogs" {
  source = "../../"

  name              = "jwall-engineering-dataset-catalogs"
  host_workspace_id = 1111111111111111
  owner_group_name  = "jwall-engineering-metastore-admins"
  apply_role_arn    = "arn:aws:iam::111122223333:role/jwall-engineering-infra-ci-apply"
}

output "url" {
  value = module.dataset_catalogs.url
}
