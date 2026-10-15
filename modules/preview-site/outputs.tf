output "distribution_id" {
  description = "CloudFront distribution ID serving `*.preview.<site_domain>`."
  value       = aws_cloudfront_distribution.this.id
}

output "url_pattern" {
  description = "URL pattern for previews: `https://pr-<n>.preview.<site_domain>`."
  value       = "https://pr-<n>.preview.${var.site_domain}"
}
