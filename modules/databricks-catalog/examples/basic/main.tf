# The workspace stack, applied after the account stack: its databricks
# provider points at the workspace the account stack created, and its inputs
# are that stack's outputs.
module "context" {
  source = "../../../context"

  project     = "databricks-poc"
  environment = "dev"
  repository  = "example/infra"

  extra_tags = {
    CostCenter = "cc-0000"
    Workspace  = "databricks-poc-dev"
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = module.context.tags
  }
}

# Workspace-level provider: host = the account stack's workspace_url output.
# Authentication comes from the environment (DATABRICKS_CLIENT_ID,
# DATABRICKS_CLIENT_SECRET); the service principal is a workspace admin.
provider "databricks" {
  host = "https://dbc-01234567-89ab.cloud.databricks.com"
}

module "catalog" {
  source = "../../"

  project          = "databricks-poc"
  workspace_id     = 1234567890123456
  admin_group_name = "databricks-poc-workspace-admins"
  users_group_name = "databricks-poc-workspace-users"

  apply_role_arn = "arn:aws:iam::111122223333:role/jwall-engineering-databricks-poc-ci-apply"
  management_role_arns = [
    "arn:aws:iam::111122223333:role/jwall-engineering-databricks-poc-ci-plan",
    "arn:aws:iam::111122223333:role/admin",
  ]

  tags = module.context.tags
}

output "catalog_name" {
  value = module.catalog.catalog_name
}
