data "databricks_group" "users" {
  display_name = var.users_group_name
}

# Every workspace user belongs to the built-in `users` group, which Databricks
# grants unrestricted cluster creation by default.
data "databricks_group" "builtin_users" {
  count = var.restrict_builtin_users_group ? 1 : 0

  display_name = "users"
}

data "databricks_current_metastore" "this" {}

locals {
  # The platform's fixed tag rules; they win over anything in a definition
  # (which validation already keeps from setting custom_tags.*).
  tag_rules = { for k, v in var.fixed_tags : "custom_tags.${k}" => { type = "fixed", value = v } }
}

resource "databricks_cluster_policy" "this" {
  for_each = var.compute_policies

  name        = each.key
  description = each.value.description
  definition  = jsonencode(merge(jsondecode(each.value.definition), local.tag_rules))
}

# CAN_USE lets users create clusters through the policy even though
# allow_cluster_create is off; that is how Databricks policies work.
resource "databricks_permissions" "policy" {
  for_each = databricks_cluster_policy.this

  cluster_policy_id = each.value.id

  access_control {
    group_name       = var.users_group_name
    permission_level = "CAN_USE"
  }
}

# databricks_entitlements is authoritative: every apply sends the full set of
# entitlements set to true, replacing the group's (attributes default to
# false), so the entitlements users need are stated explicitly.
# workspace_consume is left unset (false): it conflicts with workspace_access
# and databricks_sql_access, which stay on.
resource "databricks_entitlements" "users" {
  group_id                   = data.databricks_group.users.id
  workspace_access           = true
  databricks_sql_access      = true
  allow_cluster_create       = false
  allow_instance_pool_create = false
}

resource "databricks_entitlements" "builtin_users" {
  count = var.restrict_builtin_users_group ? 1 : 0

  group_id                   = data.databricks_group.builtin_users[0].id
  workspace_access           = true
  databricks_sql_access      = true
  allow_cluster_create       = false
  allow_instance_pool_create = false
}

resource "databricks_system_schema" "this" {
  for_each = var.enable_system_schemas ? toset(var.system_schemas) : toset([])

  schema = each.key

  lifecycle {
    precondition {
      condition     = data.databricks_current_metastore.this.id == var.metastore_id
      error_message = "The workspace is assigned to a different metastore than metastore_id; system schemas are metastore-wide, so check the metastore_id variable."
    }
  }
}

resource "databricks_disable_legacy_dbfs_setting" "this" {
  disable_legacy_dbfs {
    value = true
  }
}

resource "databricks_disable_legacy_access_setting" "this" {
  disable_legacy_access {
    value = true
  }
}

resource "databricks_workspace_conf" "this" {
  custom_config = {
    maxTokenLifetimeDays = tostring(var.max_token_lifetime_days)
  }
}
