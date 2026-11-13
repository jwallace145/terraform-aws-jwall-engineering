output "metastore_id" {
  description = "ID of the metastore, for `databricks_metastore_assignment` in each workspace stack."
  value       = databricks_metastore.this.metastore_id
}

output "admin_group_name" {
  description = "Name of the group that owns the metastore."
  value       = databricks_group.admins.display_name
}
