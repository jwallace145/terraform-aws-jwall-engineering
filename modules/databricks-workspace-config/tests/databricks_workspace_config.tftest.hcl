mock_provider "databricks" {
  override_during = plan

  mock_data "databricks_group" {
    defaults = {
      id = "1111"
    }
  }

}

override_data {
  target = data.databricks_current_metastore.this
  values = {
    id = "11111111-2222-3333-4444-555555555555"
  }
}

variables {
  users_group_name = "databricks-poc-workspace-users"
  metastore_id     = "11111111-2222-3333-4444-555555555555"

  fixed_tags = {
    CostCenter = "cc-0000"
    Project    = "databricks-poc"
  }

  compute_policies = {
    team-a-jobs = {
      description = "Single-node jobs compute"
      definition = {
        autotermination_minutes = { type = "fixed", value = 30, hidden = true }
        node_type_id            = { type = "allowlist", values = ["m5.xlarge", "m5.2xlarge"] }
        num_workers             = { type = "range", maxValue = 4 }
      }
    }
  }
}

run "fixed_tags_injected" {
  command = plan

  assert {
    condition = alltrue([
      for k, v in var.fixed_tags :
      jsondecode(databricks_cluster_policy.this["team-a-jobs"].definition)["custom_tags.${k}"] == { type = "fixed", value = v }
    ])
    error_message = "every fixed tag must be pinned as type=fixed with its value in the policy definition"
  }

  assert {
    condition     = jsondecode(databricks_cluster_policy.this["team-a-jobs"].definition)["custom_tags.CostCenter"].type == "fixed"
    error_message = "custom_tags.CostCenter must be a fixed policy rule"
  }

  assert {
    condition     = jsondecode(databricks_cluster_policy.this["team-a-jobs"].definition)["autotermination_minutes"].value == 30
    error_message = "the caller's own rules must be kept"
  }

  assert {
    condition     = databricks_cluster_policy.this["team-a-jobs"].name == "team-a-jobs"
    error_message = "the policy is named after its map key"
  }
}

run "rejects_definition_setting_custom_tags" {
  command = plan

  variables {
    compute_policies = {
      team-a-jobs = {
        description = "x"
        definition = {
          autotermination_minutes  = { type = "fixed", value = 30 }
          "custom_tags.CostCenter" = { type = "fixed", value = "cc-9999" }
        }
      }
    }
  }

  expect_failures = [var.compute_policies]
}

run "rejects_definition_without_autotermination" {
  command = plan

  variables {
    compute_policies = {
      team-a-jobs = {
        description = "x"
        definition = {
          node_type_id = { type = "fixed", value = "m5.xlarge" }
        }
      }
    }
  }

  expect_failures = [var.compute_policies]
}

run "rejects_bad_policy_name" {
  command = plan

  variables {
    compute_policies = {
      "Team A" = {
        description = "x"
        definition  = { autotermination_minutes = { type = "fixed", value = 30 } }
      }
    }
  }

  expect_failures = [var.compute_policies]
}

run "users_can_use_policies_only" {
  command = plan

  assert {
    condition = alltrue([
      for p in values(databricks_permissions.policy) :
      length(p.access_control) == 1 &&
      one(p.access_control).group_name == "databricks-poc-workspace-users" &&
      one(p.access_control).permission_level == "CAN_USE"
    ])
    error_message = "the users group must hold exactly CAN_USE on each policy"
  }

  assert {
    condition     = toset(keys(databricks_permissions.policy)) == toset(keys(var.compute_policies))
    error_message = "one permissions resource per policy"
  }
}

run "cluster_create_entitlement_off" {
  command = plan

  assert {
    condition     = databricks_entitlements.users.allow_cluster_create == false
    error_message = "the project users group must not have unrestricted cluster creation"
  }

  assert {
    condition     = databricks_entitlements.builtin_users[0].allow_cluster_create == false
    error_message = "the built-in users group (which every user belongs to) must not have unrestricted cluster creation"
  }
}

run "entitlements_explicit_on_both_groups" {
  command = plan

  assert {
    condition = alltrue([
      for e in [databricks_entitlements.users, databricks_entitlements.builtin_users[0]] :
      e.workspace_access == true &&
      e.databricks_sql_access == true &&
      e.allow_cluster_create == false &&
      e.allow_instance_pool_create == false &&
      coalesce(e.workspace_consume, false) == false
    ])
    error_message = "both groups keep workspace and SQL access (the resource replaces the whole entitlement set) and lose cluster and pool creation; workspace_consume stays off"
  }
}

run "builtin_users_group_optional" {
  command = plan

  variables {
    restrict_builtin_users_group = false
  }

  assert {
    condition     = length(databricks_entitlements.builtin_users) == 0
    error_message = "the built-in users group is left alone when restrict_builtin_users_group is false"
  }
}

run "system_schemas_off_by_default" {
  command = plan

  assert {
    condition     = length(databricks_system_schema.this) == 0
    error_message = "system schemas are enabled only when enable_system_schemas is true"
  }
}

run "system_schemas_enabled" {
  command = plan

  variables {
    enable_system_schemas = true
  }

  assert {
    condition     = toset(keys(databricks_system_schema.this)) == toset(["access", "billing", "compute", "lakeflow", "query", "storage"])
    error_message = "the default schemas are enabled"
  }
}

run "system_schemas_rejects_unknown_name" {
  command = plan

  variables {
    system_schemas = ["access", "Bogus Name"]
  }

  expect_failures = [var.system_schemas]
}

run "settings_applied" {
  command = plan

  assert {
    condition     = databricks_disable_legacy_dbfs_setting.this.disable_legacy_dbfs[0].value == true
    error_message = "legacy DBFS access is disabled"
  }

  assert {
    condition     = databricks_disable_legacy_access_setting.this.disable_legacy_access[0].value == true
    error_message = "legacy (non-Unity-Catalog) access is disabled"
  }

  assert {
    condition     = databricks_workspace_conf.this.custom_config["maxTokenLifetimeDays"] == "90"
    error_message = "personal access tokens are capped at 90 days"
  }
}

run "serverless_not_touched" {
  command = plan

  assert {
    condition     = !contains(keys(databricks_workspace_conf.this.custom_config), "enableServerlessCompute")
    error_message = "serverless compute stays enabled; no setting may disable it"
  }
}

run "outputs_policy_ids" {
  command = plan

  assert {
    condition     = toset(keys(output.cluster_policy_ids)) == toset(["team-a-jobs"])
    error_message = "cluster_policy_ids is keyed by policy name"
  }
}

run "system_schemas_reject_other_metastore" {
  command = plan

  variables {
    enable_system_schemas = true
    metastore_id          = "99999999-2222-3333-4444-555555555555"
  }

  expect_failures = [databricks_system_schema.this]
}
