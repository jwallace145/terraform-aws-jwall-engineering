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
