output "role_arn" {
  description = "ARN of the role, for `role-to-assume` in `aws-actions/configure-aws-credentials`."
  value       = module.role.arn
}

output "role_name" {
  description = "Name of the role."
  value       = module.role.name
}

output "policy_arns" {
  description = "Map of requested policy (for example `task/launch`) to the ARN of the managed policy created for it and attached to the role."
  value       = module.policies.arns
}
