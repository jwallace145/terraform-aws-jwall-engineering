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
