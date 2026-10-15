output "name" {
  description = "Bucket name (`jwall-engineering-<project>`)."
  value       = aws_s3_bucket.this.bucket
}

output "arn" {
  description = "Bucket ARN."
  value       = aws_s3_bucket.this.arn
}

output "regional_domain_name" {
  description = "Regional bucket domain name, to be used as a CloudFront origin (`<bucket>.s3.us-east-1.amazonaws.com`)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "policy" {
  description = "The bucket policy as a JSON string."
  value       = aws_s3_bucket_policy.this.policy
}
