output "name" {
  description = "Name of the bucket."
  value       = aws_s3_bucket.this.bucket
}

output "arn" {
  description = "ARN of the bucket, for IAM policies."
  value       = aws_s3_bucket.this.arn
}

output "uri" {
  description = "Where the project's data lives: `s3://<name>/<prefix>`."
  value       = "s3://${aws_s3_bucket.this.bucket}/${var.prefix}"
}
