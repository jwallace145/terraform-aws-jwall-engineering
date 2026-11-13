# Account-level provider; authentication comes from the environment
# (DATABRICKS_CLIENT_ID, DATABRICKS_CLIENT_SECRET, DATABRICKS_ACCOUNT_ID).
provider "databricks" {
  host = "https://accounts.cloud.databricks.com"
}

module "metastore" {
  source = "../../"

  admin_user_names                 = ["owner@example.com"]
  service_principal_application_id = "00000000-0000-0000-0000-000000000000"
}

output "metastore_id" {
  value = module.metastore.metastore_id
}
