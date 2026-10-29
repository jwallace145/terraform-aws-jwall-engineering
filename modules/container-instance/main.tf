# One EC2 instance that runs one image tag from ECR as the `app` container.
#
# Rollouts happen on the instance, never by replacing it: the CLI writes the
# desired tag to an SSM parameter and asks the instance (Run Command) to
# reconcile, and the reconciler swaps containers gracefully. Changing the
# AMI, the instance type or the user data REPLACES the instance, which ends
# whatever the container is doing (a game in progress is lost). Apply such
# changes only while the bot is idle.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id       = data.aws_caller_identity.current.account_id
  region           = data.aws_region.current.region
  parameter_prefix = "/${var.name_root}/${var.project}/bot"
  log_group_name   = "/${var.name_root}/${var.project}/bot"

  # A public image ID; the SSM parameter value is only marked sensitive by type.
  ami_id = var.ami_id != null ? var.ami_id : nonsensitive(data.aws_ssm_parameter.ami[0].value)

  tags = {
    Name      = var.name
    Component = var.component
  }
}

# The latest Amazon Linux 2023 image, only when no image is pinned. Following
# it replaces the instance whenever Amazon publishes a new image; pin
# `ami_id` to upgrade the OS deliberately instead.
data "aws_ssm_parameter" "ami" {
  count = var.ami_id == null ? 1 : 0

  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${var.architecture}"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days

  tags = {
    Name      = local.log_group_name
    Component = var.component
  }
}

resource "aws_security_group" "this" {
  name        = var.name
  description = "${var.name}: egress only, no ingress"
  vpc_id      = var.vpc_id

  tags = local.tags
}

# No ingress rule exists, by design: operators use Session Manager.
resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.this.id
  description       = "Lichess, ECR, SSM, CloudWatch and S3 over the internet gateway"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = local.tags
}

resource "aws_instance" "this" {
  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.this.name
  monitoring                  = false

  user_data                   = local.user_data
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  credit_specification {
    cpu_credits = "standard"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_gb
    encrypted             = true
    delete_on_termination = true

    # Volumes do not inherit the instance's tags; default_tags reach them
    # only through this block.
    tags = local.tags
  }

  tags = local.tags

  # The log group must exist before the first container logs to it.
  depends_on = [aws_cloudwatch_log_group.this, aws_iam_role_policy.this]
}
