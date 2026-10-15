output "distribution_id" {
  description = "CloudFront distribution ID (use for `aws cloudfront create-invalidation`)."
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN."
  value       = aws_cloudfront_distribution.this.arn
}

output "url" {
  description = "Public URL of the site (`https://<domain_name>`)."
  value       = "https://${var.domain_name}"
}
