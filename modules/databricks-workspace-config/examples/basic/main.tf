# The workspace stack, applied after the account stack. Its databricks provider
# points at the workspace the account stack created.
#
# Workspace-level provider: host = the account stack's workspace_url output.
# Authentication comes from the environment (DATABRICKS_CLIENT_ID,
# DATABRICKS_CLIENT_SECRET); the service principal is a workspace admin.
provider "databricks" {
  host = "https://dbc-01234567-89ab.cloud.databricks.com"
}

module "workspace_config" {
  source = "../../"

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
      description = "Small autoscaling jobs compute"
      definition = {
        autotermination_minutes = { type = "fixed", value = 30, hidden = true }
        node_type_id            = { type = "allowlist", values = ["m5.xlarge", "m5.2xlarge"] }
        num_workers             = { type = "range", maxValue = 4 }
      }
    }
  }

  # Only in the one governance workspace.
  enable_system_schemas = false
}

output "cluster_policy_ids" {
  value = module.workspace_config.cluster_policy_ids
}
