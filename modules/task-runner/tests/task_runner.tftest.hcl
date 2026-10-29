mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_data "aws_ssm_parameter" {
    defaults = {
      value = "ami-0123456789abcdef0"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/jwall-engineering-rusty-chess-task"
    }
  }

  mock_resource "aws_iam_instance_profile" {
    defaults = {
      arn = "arn:aws:iam::123456789012:instance-profile/jwall-engineering-rusty-chess-task"
    }
  }

  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-0123456789abcdef0"
    }
  }

  mock_resource "aws_launch_template" {
    defaults = {
      id = "lt-0123456789abcdef0"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/jwall-engineering/rusty-chess/tasks"
    }
  }
}

variables {
  project = "rusty-chess"
  vpc_id  = "vpc-0123"
}

run "launch_template" {
  command = plan

  assert {
    condition     = aws_launch_template.this.name == "jwall-engineering-rusty-chess-task"
    error_message = "the template is named <name_root>-<project>-task"
  }

  assert {
    condition     = aws_launch_template.this.instance_initiated_shutdown_behavior == "terminate"
    error_message = "a shutdown from inside the instance must terminate it"
  }

  assert {
    condition     = aws_launch_template.this.update_default_version
    error_message = "the CLI launches $Default, so each change must become the default version"
  }

  assert {
    condition = (
      aws_launch_template.this.metadata_options[0].http_tokens == "required" &&
      aws_launch_template.this.metadata_options[0].http_endpoint == "enabled"
    )
    error_message = "IMDSv2 must be required"
  }

  assert {
    condition     = aws_launch_template.this.instance_type == "c8a.xlarge"
    error_message = "the default instance type is c8a.xlarge"
  }

  assert {
    condition     = aws_launch_template.this.image_id == "ami-0123456789abcdef0"
    error_message = "without a pin the image comes from the public Amazon Linux 2023 parameter"
  }

  assert {
    condition     = data.aws_ssm_parameter.ami[0].name == "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
    error_message = "the parameter must match the architecture"
  }

  assert {
    condition = (
      aws_launch_template.this.block_device_mappings[0].ebs[0].volume_type == "gp3" &&
      aws_launch_template.this.block_device_mappings[0].ebs[0].volume_size == 40 &&
      aws_launch_template.this.block_device_mappings[0].ebs[0].encrypted == "true" &&
      aws_launch_template.this.block_device_mappings[0].ebs[0].delete_on_termination == "true"
    )
    error_message = "the root volume is an encrypted 40 GB gp3 volume deleted with the instance"
  }

  assert {
    condition     = aws_launch_template.this.iam_instance_profile[0].arn == aws_iam_instance_profile.this.arn
    error_message = "instances run with the task instance profile"
  }

  assert {
    condition = (
      aws_launch_template.this.vpc_security_group_ids == toset([aws_security_group.this.id]) &&
      length(aws_launch_template.this.network_interfaces) == 0
    )
    error_message = "the template sets the security group only; the CLI picks the subnet per launch"
  }

  assert {
    condition = (
      toset([for t in aws_launch_template.this.tag_specifications : t.resource_type]) == toset(["instance", "volume"]) &&
      alltrue([for t in aws_launch_template.this.tag_specifications : t.tags == tomap({ Project = "rusty-chess", Component = "task-runner", Purpose = "ci-task" })])
    )
    error_message = "instances and volumes carry Project, Component = task-runner and Purpose = ci-task, which task/launch requires as request tags"
  }

  assert {
    condition     = aws_launch_template.this.tags == tomap({ Name = "jwall-engineering-rusty-chess-task", Component = "task-runner" })
    error_message = "the template carries Name and Component = task-runner"
  }
}

run "user_data" {
  command = plan

  assert {
    condition     = startswith(base64decode(aws_launch_template.this.user_data), "#!/bin/bash\nshutdown -h +360\n")
    error_message = "the lifetime guard must be scheduled before anything else runs"
  }

  assert {
    condition = (
      strcontains(base64decode(aws_launch_template.this.user_data), "TASK_RUST_TOOLCHAIN=stable\n") &&
      strcontains(base64decode(aws_launch_template.this.user_data), "rustup") &&
      strcontains(base64decode(aws_launch_template.this.user_data), "dnf install -y git gcc")
    )
    error_message = "the setup installs git, gcc and rustup with the toolchain"
  }
}

run "lifetime_and_toolchain_follow_inputs" {
  command = plan

  variables {
    max_lifetime_hours = 2
    rust_toolchain     = "1.91.0"
    ami_id             = "ami-0fedcba9876543210"
    root_volume_gb     = 80
  }

  assert {
    condition = (
      startswith(base64decode(aws_launch_template.this.user_data), "#!/bin/bash\nshutdown -h +120\n") &&
      strcontains(base64decode(aws_launch_template.this.user_data), "TASK_RUST_TOOLCHAIN=1.91.0\n")
    )
    error_message = "the guard and the toolchain follow the inputs"
  }

  assert {
    condition     = aws_launch_template.this.image_id == "ami-0fedcba9876543210" && length(data.aws_ssm_parameter.ami) == 0
    error_message = "a pinned image is used as is"
  }

  assert {
    condition     = aws_launch_template.this.block_device_mappings[0].ebs[0].volume_size == 80
    error_message = "the root volume follows root_volume_gb"
  }
}

run "security_group" {
  command = plan

  assert {
    condition     = aws_security_group.this.name == "jwall-engineering-rusty-chess-task" && aws_security_group.this.vpc_id == "vpc-0123"
    error_message = "the task security group lives in the project's VPC"
  }

  assert {
    condition     = length(aws_security_group.this.ingress) == 0
    error_message = "no ingress"
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.all_ipv4.cidr_ipv4 == "0.0.0.0/0" && aws_vpc_security_group_egress_rule.all_ipv4.ip_protocol == "-1"
    error_message = "egress to all IPv4"
  }
}

run "instance_role" {
  command = plan

  assert {
    condition = (
      aws_iam_role.this.name == "jwall-engineering-rusty-chess-task" &&
      jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.Service == "ec2.amazonaws.com" &&
      aws_iam_instance_profile.this.role == aws_iam_role.this.name
    )
    error_message = "the role is <name_root>-<project>-task, the name task/launch may pass, trusted by EC2"
  }

  # AmazonSSMManagedInstanceCore grants ssm:GetParameter on *, which would
  # let pull request code read every parameter in the account, the bot's
  # Lichess token among them. The agent gets an inline minimum instead.
  assert {
    condition = jsonencode(jsondecode(aws_iam_role_policy.this.policy).Statement[3]) == jsonencode({
      Sid    = "RunCommandAgent"
      Effect = "Allow"
      Action = [
        "ec2messages:AcknowledgeMessage",
        "ec2messages:DeleteMessage",
        "ec2messages:FailMessage",
        "ec2messages:GetEndpoint",
        "ec2messages:GetMessages",
        "ec2messages:SendReply",
        "ssm:DescribeAssociation",
        "ssm:ListAssociations",
        "ssm:ListInstanceAssociations",
        "ssm:UpdateAssociationStatus",
        "ssm:UpdateInstanceAssociationStatus",
        "ssm:UpdateInstanceInformation",
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
      ]
      Resource = "*"
    })
    error_message = "the agent gets only Run Command's channel and registration actions"
  }

  assert {
    condition = !anytrue(flatten([
      for s in jsondecode(aws_iam_role_policy.this.policy).Statement : [
        for a in flatten([s.Action]) : startswith(a, "ssm:GetParameter") || startswith(a, "kms:") || startswith(a, "secretsmanager:") || a == "ssm:*" || a == "*"
      ]
    ]))
    error_message = "the task instance must read no parameter and no secret"
  }

  assert {
    condition     = jsonencode([for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s.Sid]) == jsonencode(["WriteTaskLogs", "FindTaskLogGroup", "WriteTaskResults", "RunCommandAgent"])
    error_message = "the inline policy has exactly the log and results statements"
  }

  assert {
    condition = jsonencode(jsondecode(aws_iam_role_policy.this.policy).Statement[0]) == jsonencode({
      Sid      = "WriteTaskLogs"
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = ["arn:aws:logs:us-east-1:123456789012:log-group:/jwall-engineering/rusty-chess/tasks", "arn:aws:logs:us-east-1:123456789012:log-group:/jwall-engineering/rusty-chess/tasks:*"]
    })
    error_message = "logs: write to the task log group only"
  }

  assert {
    condition = jsonencode(jsondecode(aws_iam_role_policy.this.policy).Statement[1]) == jsonencode({
      Sid      = "FindTaskLogGroup"
      Effect   = "Allow"
      Action   = "logs:DescribeLogGroups"
      Resource = "arn:aws:logs:us-east-1:123456789012:log-group:*"
    })
    error_message = "Run Command's CloudWatch output checks that the group exists first"
  }

  assert {
    condition = jsonencode(jsondecode(aws_iam_role_policy.this.policy).Statement[2]) == jsonencode({
      Sid      = "WriteTaskResults"
      Effect   = "Allow"
      Action   = "s3:PutObject"
      Resource = "arn:aws:s3:::jwall-engineering-rusty-chess-tasks/tasks/$${aws:userid}/*"
    })
    # An EC2 role session's aws:userid is <role-id>:<instance-id>: each instance
    # can write only its own prefix, never another task's results.
    error_message = "results: put objects under the instance's own tasks/<role-id>:<instance-id>/ prefix only"
  }
}

run "log_group" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/jwall-engineering/rusty-chess/tasks" && aws_cloudwatch_log_group.this.retention_in_days == 14
    error_message = "the task log group is /<name_root>/<project>/tasks with 14 days of retention"
  }

  assert {
    condition = (
      output.log_group_name == "/jwall-engineering/rusty-chess/tasks" &&
      output.results_uri == "s3://jwall-engineering-rusty-chess-tasks/tasks/" &&
      output.launch_template_name == "jwall-engineering-rusty-chess-task" &&
      output.instance_role_name == "jwall-engineering-rusty-chess-task"
    )
    error_message = "outputs expose the names the CLI derives"
  }
}

run "rejects_long_lifetime" {
  command = plan

  variables {
    max_lifetime_hours = 25
  }

  expect_failures = [var.max_lifetime_hours]
}

run "rejects_malformed_instance_type" {
  command = plan

  variables {
    default_instance_type = "c8a xlarge"
  }

  expect_failures = [var.default_instance_type]
}

run "rejects_unsafe_toolchain" {
  command = plan

  variables {
    rust_toolchain = "stable; rm -rf /"
  }

  expect_failures = [var.rust_toolchain]
}
