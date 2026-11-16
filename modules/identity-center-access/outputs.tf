output "user_id" {
  description = "Identity store ID of the user."
  value       = aws_identitystore_user.this.user_id
}

output "user_name" {
  description = "User name the person signs in to the access portal with."
  value       = aws_identitystore_user.this.user_name
}

output "permission_set_arn" {
  description = "ARN of the permission set."
  value       = aws_ssoadmin_permission_set.this.arn
}

output "permission_set_name" {
  description = "Name of the permission set: the `sso_role_name` of an AWS CLI profile."
  value       = aws_ssoadmin_permission_set.this.name
}

output "session_duration" {
  description = "Session duration of the permission set, as an ISO-8601 duration."
  value       = aws_ssoadmin_permission_set.this.session_duration
}

output "role_arn" {
  description = "Full ARN, path included, of the IAM role Identity Center provisioned for the permission set (`arn:aws:iam::<account>:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_<name>_<suffix>`): the value `aws:PrincipalArn` takes in bucket policies. Null until IAM lists the role; run `terraform apply -refresh-only` if it is null after the first apply."
  value       = try(one(data.aws_iam_roles.provisioned.arns), null)
}
