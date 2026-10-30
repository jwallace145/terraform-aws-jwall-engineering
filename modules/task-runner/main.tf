# Prepares a project's ephemeral task instances; it launches none.
#
# One instance of this module is one task *profile*: a launch template and
# an instance role. The `cpu` profile is `<name_root>-<project>-task`; any
# other is `<name_root>-<project>-task-<profile>`. The log group and the
# security group belong to the project: the first profile creates them, and
# every other profile reuses them through `shared`.
#
# The jwall-engineering-sites CLI launches each task instance from this
# template, runs one task on it through SSM Run Command and terminates it.
# The names below are fixed by the `task/launch` CI policy: the launch role
# may pass only `<name_root>-<project>-task`, write results only under
# `<name_root>-<project>-tasks/tasks/` and read only `/<name_root>/<project>/tasks`.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id     = data.aws_caller_identity.current.account_id
  region         = data.aws_region.current.region
  base_name      = "${var.name_root}-${var.project}-task"
  name           = var.profile == "cpu" ? local.base_name : "${local.base_name}-${var.profile}"
  log_group_name = var.shared == null ? "/${var.name_root}/${var.project}/tasks" : var.shared.log_group_name
  log_group_arn  = "arn:aws:logs:${local.region}:${local.account_id}:log-group:${local.log_group_name}"
  security_group = var.shared == null ? aws_security_group.this[0].id : var.shared.security_group_id

  # Descriptions name the profile only beyond cpu: the cpu profile keeps the
  # wording it had before profiles, because changing a role's description
  # needs iam:UpdateRoleDescription, which the stacks' apply roles lack.
  profile_suffix = var.profile == "cpu" ? "" : ", profile ${var.profile}"
  results_bucket = "${var.name_root}-${var.project}-tasks"
  results_prefix = "tasks/"

  # A public image ID; the SSM parameter value is only marked sensitive by type.
  ami_id = var.ami_id != null ? var.ami_id : nonsensitive(data.aws_ssm_parameter.ami[0].value)

  tags = {
    Name      = local.name
    Component = "task-runner"
    Profile   = var.profile
  }

  # Launched instances and volumes. `task/launch` requires Project and
  # Purpose as request tags on both; the CLI sends them too, with the other
  # organisation tags, `Name` and the run's tags, because RunInstances does
  # not apply the provider's default tags.
  launch_tags = {
    Project   = var.project
    Component = "task-runner"
    Purpose   = "ci-task"
    Profile   = var.profile
  }

  # The lifetime guard comes first, before anything that can fail: a
  # shutdown terminates the instance (instance_initiated_shutdown_behavior).
  user_data = join("\n", [
    "#!/bin/bash",
    "shutdown -h +${var.max_lifetime_hours * 60}",
    "TASK_RUST_TOOLCHAIN=${var.rust_toolchain}",
    "TASK_GPU=${var.gpu ? 1 : 0}",
    file("${path.module}/files/task-setup.sh"),
  ])
}

# The latest Amazon Linux 2023 image, only when no image is pinned. Each
# task gets a fresh instance, so following it replaces nothing.
data "aws_ssm_parameter" "ami" {
  count = var.ami_id == null ? 1 : 0

  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${var.architecture}"
}

resource "aws_cloudwatch_log_group" "this" {
  count = var.shared == null ? 1 : 0

  name              = local.log_group_name
  retention_in_days = var.log_retention_days

  tags = {
    Name      = local.log_group_name
    Component = "task-runner"
  }
}

resource "aws_security_group" "this" {
  count = var.shared == null ? 1 : 0

  name        = local.name
  description = "${local.name}: egress only, no ingress"
  vpc_id      = var.vpc_id

  tags = local.tags
}

# No ingress rule exists, by design: tasks run through Run Command.
resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  count = var.shared == null ? 1 : 0

  security_group_id = aws_security_group.this[0].id
  description       = "GitHub, crates.io, rustup, SSM, CloudWatch and S3 over the internet gateway"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = local.tags
}

resource "aws_launch_template" "this" {
  name        = local.name
  description = "Ephemeral CI task instances of ${var.project}${local.profile_suffix}"

  image_id      = local.ami_id
  instance_type = var.default_instance_type

  # The CLI launches `$Default`, so every change becomes the default.
  update_default_version = true

  instance_initiated_shutdown_behavior = "terminate"

  iam_instance_profile {
    arn = aws_iam_instance_profile.this.arn
  }

  # No network_interfaces block: the CLI passes the subnet per launch, so
  # it can try the next availability zone when one has no capacity. The
  # project's public subnets assign public IPs.
  vpc_security_group_ids = [local.security_group]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume_gb
      encrypted             = "true"
      delete_on_termination = "true"
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.launch_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.launch_tags
  }

  user_data = base64encode(local.user_data)

  tags = local.tags
}

# The log group and security group became optional with `shared`; the
# project's first profile keeps the ones it already has.
moved {
  from = aws_cloudwatch_log_group.this
  to   = aws_cloudwatch_log_group.this[0]
}

moved {
  from = aws_security_group.this
  to   = aws_security_group.this[0]
}

moved {
  from = aws_vpc_security_group_egress_rule.all_ipv4
  to   = aws_vpc_security_group_egress_rule.all_ipv4[0]
}
