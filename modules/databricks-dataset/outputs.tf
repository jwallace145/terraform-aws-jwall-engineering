output "role_arn" {
  description = "ARN of the dataset's IAM role, which reads only once the dataset's bucket policy names it as a reader."
  value       = aws_iam_role.this.arn
}

output "storage_credential_name" {
  description = "Name of the read-only storage credential (the dataset's name)."
  value       = databricks_storage_credential.this.name
}

output "external_location_name" {
  description = "Name of the read-only external location (the dataset's name): what `databricks-dataset-access` binds and grants."
  value       = databricks_external_location.this.name
}

output "url" {
  description = "The location's URL, `s3://<bucket>/<prefix>` without the trailing slash."
  value       = databricks_external_location.this.url
}

output "endpoint_dataset" {
  description = "The entry each consumer passes to `databricks-workspace`'s `read_only_datasets`. Built from names, so it is known before the role exists."
  value = {
    bucket   = var.bucket
    prefix   = var.prefix
    role_arn = local.role_arn
  }
}

output "schema_full_name" {
  description = "`<catalog>.<schema>`, the dataset's schema; null without `catalog_name`. Built from names, so it is known before the schema exists."
  value       = var.catalog_name != null ? "${var.catalog_name}.${var.schema_name}" : null
}

output "volume_full_name" {
  description = "`<catalog>.<schema>.files`, the dataset's external volume; null without `catalog_name`."
  value       = var.catalog_name != null ? "${var.catalog_name}.${var.schema_name}.files" : null
}

output "volume_path" {
  description = "`/Volumes/<catalog>/<schema>/files`, the path consumers read; null without `catalog_name`."
  value       = var.catalog_name != null ? "/Volumes/${var.catalog_name}/${var.schema_name}/files" : null
}

