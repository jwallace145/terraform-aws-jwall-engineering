output "bucket_name" {
  description = "Name of the audit log bucket."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "ARN of the audit log bucket, for IAM policies of principals that share it (for example under `events/`)."
  value       = aws_s3_bucket.this.arn
}

output "log_delivery_config_id" {
  description = "ID of the Databricks log delivery configuration."
  value       = databricks_mws_log_delivery.audit.config_id
}
