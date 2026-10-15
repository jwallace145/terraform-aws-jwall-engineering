output "prod_distribution_id" {
  description = "CloudFront distribution ID for the production site."
  value       = module.prod.distribution_id
}

output "prod_distribution_arn" {
  description = "CloudFront distribution ARN for the production site."
  value       = module.prod.distribution_arn
}

output "prod_url" {
  description = "Production URL (`https://<domain_name>`)."
  value       = module.prod.url
}

output "dev_distribution_id" {
  description = "CloudFront distribution ID for the dev site, or `null` when `dev_domain_name` is not set."
  value       = one(module.dev[*].distribution_id)
}

output "dev_url" {
  description = "Dev URL (`https://<dev_domain_name>`), or `null` when `dev_domain_name` is not set."
  value       = one(module.dev[*].url)
}

output "preview_distribution_id" {
  description = "CloudFront distribution ID for `*.preview.<domain_name>`, or `null` when `enable_preview` is false."
  value       = one(module.preview[*].distribution_id)
}

output "preview_url_pattern" {
  description = "Preview URL pattern (`https://pr-<n>.preview.<domain_name>`), or `null` when `enable_preview` is false."
  value       = one(module.preview[*].url_pattern)
}

output "distribution_ids" {
  description = "Map of environment name (`prod`, `dev`, `preview`) to CloudFront distribution ID, for invalidation scripts."
  value = merge(
    { prod = module.prod.distribution_id },
    { for m in module.dev : "dev" => m.distribution_id },
    { for m in module.preview : "preview" => m.distribution_id },
  )
}
