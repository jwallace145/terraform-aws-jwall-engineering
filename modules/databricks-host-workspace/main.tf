# The account's shared-objects host: a serverless workspace that exists only
# so metastore-level objects that must be created through a workspace (shared
# datasets' storage credentials, read-only external locations, their
# bindings to other workspaces and their grants) have a home that no project
# owns. Serverless means no customer VPC, NAT, cross-account role or root
# bucket: it has no standing AWS cost. It has no users and no compute
# policies; only the metastore admin group (the people who administer the
# metastore and the automation service principal) is assigned to it.
resource "databricks_mws_workspaces" "this" {
  account_id     = var.account_id
  workspace_name = var.workspace_name
  aws_region     = var.region
  pricing_tier   = "PREMIUM"
  compute_mode   = "SERVERLESS"

  custom_tags = var.tags
}

resource "databricks_metastore_assignment" "this" {
  workspace_id = databricks_mws_workspaces.this.workspace_id
  metastore_id = var.metastore_id
}

data "databricks_group" "admins" {
  display_name = var.admin_group_name
}

# Account groups reach a workspace only once it has identity federation,
# which the metastore assignment turns on.
resource "databricks_mws_permission_assignment" "admins" {
  workspace_id = databricks_mws_workspaces.this.workspace_id
  principal_id = tonumber(data.databricks_group.admins.id)
  permissions  = ["ADMIN"]

  depends_on = [databricks_metastore_assignment.this]
}
