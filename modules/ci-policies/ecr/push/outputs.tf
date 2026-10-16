output "arn" {
  description = "ARN of the managed policy."
  value       = aws_iam_policy.this.arn
}

output "name" {
  description = "Name of the managed policy."
  value       = aws_iam_policy.this.name
}

output "policy" {
  description = "The policy document as a JSON string."
  value       = aws_iam_policy.this.policy
}
