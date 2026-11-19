output "arn" {
  description = "The role's ARN, `arn:aws:iam::<account>:role/aws-service-role/<service>/<name>`."
  value       = aws_iam_service_linked_role.this.arn
}

output "name" {
  description = "The role's name, which AWS chooses per service (for example `AWSServiceRoleForEC2Spot`)."
  value       = aws_iam_service_linked_role.this.name
}
