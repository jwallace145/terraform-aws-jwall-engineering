output "name" {
  description = "Name of the state bucket, for the `bucket` argument of an `s3` backend."
  value       = aws_s3_bucket.this.id
}

output "arn" {
  description = "ARN of the state bucket, for CI role policies (`state_bucket_arn` of `site-ci-roles` and `infra-ci-roles`)."
  value       = aws_s3_bucket.this.arn
}
