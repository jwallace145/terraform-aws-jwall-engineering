output "instance_id" {
  description = "ID of the instance, for Session Manager (`aws ssm start-session --target`) and Run Command."
  value       = aws_instance.this.id
}

output "instance_arn" {
  description = "ARN of the instance."
  value       = aws_instance.this.arn
}

output "public_ip" {
  description = "Public IPv4 address of the instance (egress only; nothing listens)."
  value       = aws_instance.this.public_ip
}

output "security_group_id" {
  description = "ID of the egress-only security group."
  value       = aws_security_group.this.id
}

output "role_arn" {
  description = "ARN of the instance role."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the instance role."
  value       = aws_iam_role.this.name
}

output "log_group_name" {
  description = "CloudWatch log group the container logs to."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN of the log group."
  value       = aws_cloudwatch_log_group.this.arn
}

output "parameter_prefix" {
  description = "SSM path of the bot's parameters: `/<name_root>/<project>/bot`."
  value       = local.parameter_prefix
}

output "parameter_names" {
  description = "The parameters the release tooling and the reconciler share: `desired_version` (written by a deploy), `running_version` and `status` (written by the reconciler), `last_sync` (written by the records sync)."
  value = {
    desired_version = "${local.parameter_prefix}/desired-version"
    running_version = "${local.parameter_prefix}/running-version"
    status          = "${local.parameter_prefix}/status"
    last_sync       = "${local.parameter_prefix}/last-sync"
  }
}

output "records_uri" {
  description = "S3 URI the game records are shipped under, or null without a records bucket."
  value       = var.records_bucket_name == null ? null : "s3://${var.records_bucket_name}/${var.records_prefix}"
}

output "reconciler_script" {
  description = "Internal: the installed reconciler script text, for tests."
  value       = local.reconcile_script
}

output "records_sync_script" {
  description = "Internal: the installed records sync script text, for tests."
  value       = local.records_sync_script
}
