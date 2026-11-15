data "databricks_group" "users" {
  display_name = var.users_group_name
}

# Every workspace user belongs to the built-in `users` group, so if it could
# create clusters freely the policies would mean nothing. It is checked, not
# written: new workspaces give it no entitlements and refuse changes to it
# ("Entitlement modifications on the workspace-users and admins groups are not
# permitted for this workspace"). An older workspace that grants it cluster or
# pool creation fails the plan until an admin removes them.
data "databricks_group" "builtin_users" {
  count = var.restrict_builtin_users_group ? 1 : 0

  display_name = "users"
}

# System schemas are not managed here: Databricks enables them itself (state
# MANAGED), and databricks_system_schema reads a MANAGED schema as absent.
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

  lifecycle {
    precondition {
      condition = alltrue([
        for g in data.databricks_group.builtin_users :
        !coalesce(g.allow_cluster_create, false) && !coalesce(g.allow_instance_pool_create, false)
      ])
      error_message = "The workspace's built-in users group can create clusters or instance pools, which bypasses the compute policies. Remove those entitlements in the workspace (Settings > Identity and access > Groups > users), or set restrict_builtin_users_group = false if the group is managed elsewhere."
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

  lifecycle {
    precondition {
      condition     = data.databricks_current_metastore.this.id == var.metastore_id
      error_message = "The workspace is assigned to a different metastore than metastore_id; check the metastore_id variable."
    }
  }
}
