output "role_arn" {
  description = "ARN of the dataset's Unity Catalog role (`<name_root>-<name>-databricks-share`): the one principal the producer names as a reader of the dataset."
  value       = aws_iam_role.this.arn
}

output "external_location_name" {
  description = "Name of the shared, read-only external location (`<name_root>-<name>`)."
  value       = databricks_external_location.this.name
}

output "url" {
  description = "URL of the external location, `s3://<bucket>/<prefix>` without the trailing slash: the path consumers read."
  value       = databricks_external_location.this.url
}

output "endpoint_dataset" {
  description = "The entry each consumer passes to `databricks-workspace`'s `read_only_datasets` under the dataset's name. Built from names, so it is known before the role exists."
  value = {
    bucket   = var.bucket
    prefix   = var.prefix
    role_arn = local.role_arn
  }
}
