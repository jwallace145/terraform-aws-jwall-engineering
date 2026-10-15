output "tags" {
  description = "Tag map for the caller's provider `default_tags`: Organization, Project, Environment, Repository, ManagedBy=terraform and Owner, merged over `extra_tags` (required keys win)."
  value       = local.tags
}

output "name_prefix" {
  description = "Resource name prefix: `jwall-engineering-<project>-<environment>`."
  value       = local.name_prefix
}

output "bucket_name" {
  description = "Site bucket name for the project: `jwall-engineering-<project>`. Shared by every environment of the project."
  value       = local.bucket_name
}
