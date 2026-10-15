output "arn" {
  description = "ARN of the role, for `role-to-assume` in `aws-actions/configure-aws-credentials`."
  value       = aws_iam_role.this.arn
}

output "name" {
  description = "Name of the role."
  value       = aws_iam_role.this.name
}

output "id" {
  description = "ID of the role (the same as its name)."
  value       = aws_iam_role.this.id
}

output "assume_role_policy" {
  description = "The role's trust policy as a JSON string. Exposed so composing modules can test the trust policy."
  value       = aws_iam_role.this.assume_role_policy
}

output "tags" {
  description = "Tags the module sets on the role (`Component`, and `Name` when `name_tag` is set). Excludes provider `default_tags`."
  value       = aws_iam_role.this.tags
}

output "inline_policies" {
  description = "Map of `inline_policies` key to `{ name, policy }`, where `policy` is the JSON document attached to the role."
  value = {
    for k, p in aws_iam_role_policy.this : k => {
      name   = p.name
      policy = p.policy
    }
  }
}

output "managed_policy_arns" {
  description = "ARNs of the managed policies attached to the role, sorted."
  value       = sort(keys(aws_iam_role_policy_attachment.this))
}
