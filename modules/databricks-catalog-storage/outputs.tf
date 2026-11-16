output "external_location_name" {
  description = "Name of the external location the catalogs' managed locations sit under."
  value       = databricks_external_location.this.name
}

output "url" {
  description = "The location's URL, `s3://<name>/managed`: each catalog's `storage_root` is `<url>/<catalog>`."
  value       = local.url
}

output "storage_credential_name" {
  description = "Name of the storage credential."
  value       = databricks_storage_credential.this.name
}

output "bucket_name" {
  description = "Name of the bucket."
  value       = aws_s3_bucket.this.bucket
}

output "uc_role_arn" {
  description = "ARN of the Unity Catalog role, the only principal that may read or write the bucket's objects."
  value       = local.uc_role_arn
}
