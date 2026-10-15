output "plan_role_arn" {
  description = "ARN of `<name_root>-<project>-ci-plan`, assumed by `pull_request` workflows to run `terraform plan`."
  value       = module.plan.arn
}

output "plan_role_name" {
  description = "Name of the plan role."
  value       = module.plan.name
}

output "apply_role_arn" {
  description = "ARN of `<name_root>-<project>-ci-apply`, assumed by jobs in the `apply_environment` GitHub environment to run `terraform apply`."
  value       = module.apply.arn
}

output "apply_role_name" {
  description = "Name of the apply role."
  value       = module.apply.name
}
