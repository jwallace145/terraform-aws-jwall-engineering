output "name" {
  description = "Name of the state bucket, for the `bucket` argument of an `s3` backend."
  value       = aws_s3_bucket.this.id
}

output "arn" {
  description = "ARN of the state bucket, for CI role policies (`policy_inputs.tfstate.bucket_arn` and `policy_inputs.foundation.state_bucket_arn` of the CI role modules)."
  value       = aws_s3_bucket.this.arn
}
