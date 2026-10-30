output "launch_template_id" {
  description = "ID of the task launch template."
  value       = aws_launch_template.this.id
}

output "launch_template_name" {
  description = "Name of the task launch template, `<name_root>-<project>-task`. The CLI launches its `$Default` version."
  value       = aws_launch_template.this.name
}

output "instance_role_name" {
  description = "Name of the task instance role, the only role the launch role may pass."
  value       = aws_iam_role.this.name
}

output "instance_profile_arn" {
  description = "ARN of the task instance profile."
  value       = aws_iam_instance_profile.this.arn
}

output "security_group_id" {
  description = "ID of the task security group: egress only."
  value       = local.security_group
}

output "log_group_name" {
  description = "CloudWatch log group that Run Command streams task output to."
  value       = local.log_group_name
}

output "results_uri" {
  description = "S3 prefix under which each task's outputs land, as `<results_uri><role-id>:<instance-id>/`: an instance can write only its own. The bucket is the caller's."
  value       = "s3://${local.results_bucket}/${local.results_prefix}"
}

output "shared" {
  description = "The project's log group and security group, for the `shared` input of the project's other profiles."
  value = {
    log_group_name    = local.log_group_name
    security_group_id = local.security_group
  }
}

output "profile" {
  description = "The profile this instance of the module prepares: the `Profile` tag of its template, role and instances."
  value       = var.profile
}
