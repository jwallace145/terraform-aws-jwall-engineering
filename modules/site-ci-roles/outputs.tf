output "plan_role_arn" {
  description = "ARN of `jwall-engineering-<project>-ci-plan`, assumed by `pull_request` workflows to run `terraform plan`."
  value       = aws_iam_role.this["plan"].arn
}

output "preview_role_arn" {
  description = "ARN of `jwall-engineering-<project>-ci-preview`, assumed by `pull_request` workflows to publish `previews/pr-<n>/`."
  value       = aws_iam_role.this["preview"].arn
}

output "apply_role_arn" {
  description = "ARN of `jwall-engineering-<project>-ci-apply`, assumed by the `prod` environment to run `terraform apply` and publish `prod/` and `dev/`."
  value       = aws_iam_role.this["apply"].arn
}
