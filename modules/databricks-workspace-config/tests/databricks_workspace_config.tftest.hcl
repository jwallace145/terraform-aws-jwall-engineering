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
    Project     = "databricks-poc"
    Environment = "dev"
    CostCenter  = "cc-0000"
    Workspace   = "databricks-poc-dev"
    Owner       = "team-a"
    ManagedBy   = "terraform"
  }

  compute_policies = {
    team-a-jobs = {
      description = "Single-node jobs compute"
      definition = jsonencode({
        autotermination_minutes = { type = "fixed", value = 30, hidden = true }
        node_type_id            = { type = "allowlist", values = ["m5.xlarge", "m5.2xlarge"] }
        num_workers             = { type = "range", maxValue = 4 }
      })
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
        definition = jsonencode({
          autotermination_minutes  = { type = "fixed", value = 30 }
          "custom_tags.CostCenter" = { type = "fixed", value = "cc-9999" }
        })
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
        definition = jsonencode({
          node_type_id = { type = "fixed", value = "m5.xlarge" }
        })
      }
    }
  }

  expect_failures = [var.compute_policies]
}

run "rejects_non_json_definition" {
  command = plan

  variables {
    compute_policies = {
      team-a-jobs = {
        description = "x"
        definition  = "autotermination_minutes = 30"
      }
    }
  }

  expect_failures = [var.compute_policies]
}

run "rejects_non_object_definition" {
  command = plan

  variables {
    compute_policies = {
      team-a-jobs = {
        description = "x"
        definition  = jsonencode(["autotermination_minutes"])
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
        definition  = jsonencode({ autotermination_minutes = { type = "fixed", value = 30 } })
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
}

run "entitlements_explicit_on_users_group" {
  command = plan

  assert {
    condition = (
      databricks_entitlements.users.workspace_access == true &&
      databricks_entitlements.users.databricks_sql_access == true &&
      databricks_entitlements.users.allow_cluster_create == false &&
      databricks_entitlements.users.allow_instance_pool_create == false &&
      coalesce(databricks_entitlements.users.workspace_consume, false) == false
    )
    error_message = "the users group keeps workspace and SQL access (the resource replaces the whole entitlement set) and loses cluster and pool creation; workspace_consume stays off"
  }
}

# The built-in `users` group is checked, not written: new workspaces refuse
# entitlement changes on it ("Entitlement modifications on the workspace-users
# and admins groups are not permitted for this workspace") and already give it
# none. The plan fails if it can create clusters or instance pools. The
# failing path cannot be mocked: the data source's entitlement attributes are
# optional, not computed, so overrides cannot set them. Checked live instead
# (the provider reads admins as true and the new workspace's users as false).
run "builtin_users_group_is_checked_not_written" {
  command = plan

  assert {
    condition     = length(data.databricks_group.builtin_users) == 1
    error_message = "the built-in users group is read so its entitlements can be checked"
  }
}

run "builtin_users_group_optional" {
  command = plan

  variables {
    restrict_builtin_users_group = false
  }

  assert {
    condition     = length(data.databricks_group.builtin_users) == 0
    error_message = "the built-in users group is not read when restrict_builtin_users_group is false"
  }
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

# System schemas are not managed: Databricks enables them itself (state
# MANAGED), and the provider's databricks_system_schema reads a MANAGED schema
# as absent ("Root object was present, but now absent").
run "workspace_rejects_other_metastore" {
  command = plan

  variables {
    metastore_id = "99999999-2222-3333-4444-555555555555"
  }

  expect_failures = [databricks_workspace_conf.this]
}

run "rejects_fixed_tags_missing_owner" {
  command = plan

  variables {
    fixed_tags = {
      Project     = "databricks-poc"
      Environment = "dev"
      CostCenter  = "cc-0000"
      Workspace   = "databricks-poc-dev"
      ManagedBy   = "terraform"
    }
  }

  expect_failures = [var.fixed_tags]
}

run "rejects_reserved_fixed_tag_key" {
  command = plan

  variables {
    fixed_tags = {
      Project     = "databricks-poc"
      Environment = "dev"
      CostCenter  = "cc-0000"
      Workspace   = "databricks-poc-dev"
      Owner       = "team-a"
      ManagedBy   = "terraform"
      Vendor      = "someone"
    }
  }

  expect_failures = [var.fixed_tags]
}

run "two_differently_shaped_policies_plan" {
  command = plan

  variables {
    compute_policies = {
      team-a-jobs = {
        description = "Jobs compute"
        definition = jsonencode({
          num_workers                   = { type = "range", maxValue = 4 }
          node_type_id                  = { type = "fixed", value = "m5.xlarge" }
          autotermination_minutes       = { type = "fixed", value = 30 }
          "aws_attributes.availability" = { type = "fixed", value = "SPOT_WITH_FALLBACK" }
        })
      }
      team-a-shared = {
        description = "Shared compute"
        definition = jsonencode({
          cluster_type                  = { type = "fixed", value = "all-purpose" }
          num_workers                   = { type = "fixed", value = 2 }
          node_type_id                  = { type = "allowlist", values = ["m5.xlarge", "m5.2xlarge"] }
          autotermination_minutes       = { type = "fixed", value = 60 }
          "aws_attributes.availability" = { type = "fixed", value = "ON_DEMAND" }
        })
      }
    }
  }

  assert {
    condition     = toset(keys(databricks_cluster_policy.this)) == toset(["team-a-jobs", "team-a-shared"])
    error_message = "both policies are planned"
  }

  assert {
    condition = (
      !contains(keys(jsondecode(databricks_cluster_policy.this["team-a-jobs"].definition)), "cluster_type") &&
      jsondecode(databricks_cluster_policy.this["team-a-shared"].definition)["cluster_type"].value == "all-purpose" &&
      jsondecode(databricks_cluster_policy.this["team-a-jobs"].definition)["autotermination_minutes"].value == 30 &&
      jsondecode(databricks_cluster_policy.this["team-a-shared"].definition)["autotermination_minutes"].value == 60
    )
    error_message = "each policy keeps its own differently shaped rules"
  }

  assert {
    condition = alltrue([
      for name, p in databricks_cluster_policy.this :
      jsondecode(p.definition)["custom_tags.Owner"] == { type = "fixed", value = "team-a" }
    ])
    error_message = "fixed tags are injected into both policies"
  }
}
