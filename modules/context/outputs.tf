output "tags" {
  description = "Tag map for the caller's provider `default_tags`: Organization, Project, Environment, Repository, ManagedBy and Owner, merged over `extra_tags` (required keys win)."
  value       = local.tags
}

output "name_prefix" {
  description = "Resource name prefix: `<name_root>-<project>-<environment>`."
  value       = local.name_prefix
}

output "bucket_name" {
  description = "Site bucket name for the project: `<name_root>-<project>`. Shared by every environment of the project."
  value       = local.bucket_name
}
