# One Unity Catalog metastore per region per account. Deliberately no
# storage_root: catalogs get their own managed locations (one bucket per
# project), so nothing is ever written to a metastore-level bucket.
resource "databricks_group" "admins" {
  display_name = var.admin_group_name
}

resource "databricks_metastore" "this" {
  name   = var.name
  region = var.region
  owner  = databricks_group.admins.display_name
}

data "databricks_user" "admins" {
  for_each = toset(var.admin_user_names)

  user_name = each.value
}

resource "databricks_group_member" "users" {
  for_each = data.databricks_user.admins

  group_id  = databricks_group.admins.id
  member_id = each.value.id
}

data "databricks_service_principal" "automation" {
  application_id = var.service_principal_application_id
}

resource "databricks_group_member" "service_principal" {
  group_id  = databricks_group.admins.id
  member_id = data.databricks_service_principal.automation.sp_id
}
