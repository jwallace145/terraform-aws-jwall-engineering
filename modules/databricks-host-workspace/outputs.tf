output "workspace_id" {
  description = "Numeric ID of the host workspace."
  value       = databricks_mws_workspaces.this.workspace_id
}

output "workspace_url" {
  description = "URL of the host workspace: the `host` of the workspace-level `databricks` provider that manages shared objects (`databricks-shared-dataset`)."
  value       = databricks_mws_workspaces.this.workspace_url
}
