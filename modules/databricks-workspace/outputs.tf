output "workspace_id" {
  description = "Numeric ID of the workspace."
  value       = databricks_mws_workspaces.this.workspace_id
}

output "workspace_url" {
  description = "URL of the workspace, for example `https://dbc-01234567-89ab.cloud.databricks.com`: the `host` of the workspace stack's `databricks` provider."
  value       = databricks_mws_workspaces.this.workspace_url
}

output "admin_group_name" {
  description = "Account group with ADMIN on the workspace (`<project>-workspace-admins`)."
  value       = databricks_group.admins.display_name
}

output "users_group_name" {
  description = "Account group with USER on the workspace (`<project>-workspace-users`)."
  value       = databricks_group.users.display_name
}

output "root_bucket_name" {
  description = "Name of the workspace root bucket (`<p>-databricks-root`)."
  value       = aws_s3_bucket.root.bucket
}

output "cross_account_role_arn" {
  description = "ARN of the cross-account role Databricks assumes to run clusters in the VPC."
  value       = aws_iam_role.cross_account.arn
}

output "security_group_id" {
  description = "ID of the workspace clusters' security group."
  value       = aws_security_group.this.id
}
