output "name" {
  description = "Name of the bucket, for `aws s3 sync` targets and IAM policies."
  value       = aws_s3_bucket.this.bucket
}

output "arn" {
  description = "ARN of the bucket, for IAM policies."
  value       = aws_s3_bucket.this.arn
}
