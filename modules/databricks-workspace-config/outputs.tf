output "cluster_policy_ids" {
  description = "IDs of the installed cluster policies, keyed by policy name."
  value       = { for k, p in databricks_cluster_policy.this : k => p.id }
}
