output "catalog_name" {
  description = "Name of the workspace's catalog: the project in snake_case, for example `databricks_poc`."
  value       = databricks_catalog.this.name
}

output "bucket_name" {
  description = "Name of the catalog bucket (`<p>-databricks-catalog`); Unity Catalog managed storage is under `managed/`."
  value       = aws_s3_bucket.this.bucket
}

output "uc_role_arn" {
  description = "ARN of the Unity Catalog role (`<p>-databricks-uc`), the only principal that may read or write the bucket's objects."
  value       = aws_iam_role.uc.arn
}

output "storage_credential_name" {
  description = "Name of the Unity Catalog storage credential for the role."
  value       = databricks_storage_credential.this.name
}

output "external_location_name" {
  description = "Name of the Unity Catalog external location at `s3://<bucket>/managed/`, the catalog's storage root."
  value       = databricks_external_location.this.name
}
