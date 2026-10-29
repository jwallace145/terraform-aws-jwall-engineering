data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account = data.aws_caller_identity.current.account_id
  region  = data.aws_region.current.region
  prefix  = "${var.name_root}-${var.project}"
  ec2     = "arn:aws:ec2:${local.region}:${local.account}"
  bucket  = "arn:aws:s3:::${local.prefix}-tasks"

  task_tags = {
    "aws:RequestTag/Project" = var.project
    "aws:RequestTag/Purpose" = "ci-task"
  }

  # For the role a consumer repository's pull requests and main branch assume
  # to run one task on a fresh instance: launch it from the project's template,
  # send it the task, read the task's output, terminate it. Nothing else.
  policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RunFromProjectTemplate"
        Effect   = "Allow"
        Action   = "ec2:RunInstances"
        Resource = "${local.ec2}:launch-template/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project"   = var.project
            "aws:ResourceTag/Component" = "task-runner"
          }
        }
      },
      {
        # Requiring the ec2:LaunchTemplate key means a launch without a
        # template is denied; RunFromProjectTemplate limits which template.
        Sid      = "RunTaskInstances"
        Effect   = "Allow"
        Action   = "ec2:RunInstances"
        Resource = "${local.ec2}:instance/*"
        Condition = {
          ArnLike      = { "ec2:LaunchTemplate" = "${local.ec2}:launch-template/*" }
          StringEquals = merge(local.task_tags, { "ec2:InstanceType" = var.instance_types })
        }
      },
      {
        Sid       = "RunTaskVolumes"
        Effect    = "Allow"
        Action    = "ec2:RunInstances"
        Resource  = "${local.ec2}:volume/*"
        Condition = { StringEquals = local.task_tags }
      },
      {
        Sid       = "RunFromAmazonImages"
        Effect    = "Allow"
        Action    = "ec2:RunInstances"
        Resource  = "arn:aws:ec2:${local.region}::image/*"
        Condition = { StringEquals = { "ec2:Owner" = "amazon" } }
      },
      {
        Sid    = "RunInProjectNetwork"
        Effect = "Allow"
        Action = "ec2:RunInstances"
        Resource = [
          "${local.ec2}:subnet/*",
          "${local.ec2}:security-group/*",
        ]
        Condition = { StringEquals = { "aws:ResourceTag/Project" = var.project } }
      },
      {
        # The launch creates the instance's network interface.
        Sid      = "RunWithNewInterface"
        Effect   = "Allow"
        Action   = "ec2:RunInstances"
        Resource = "${local.ec2}:network-interface/*"
      },
      {
        Sid    = "TagOnLaunch"
        Effect = "Allow"
        Action = "ec2:CreateTags"
        Resource = [
          "${local.ec2}:instance/*",
          "${local.ec2}:volume/*",
          "${local.ec2}:network-interface/*",
        ]
        Condition = { StringEquals = { "ec2:CreateAction" = "RunInstances" } }
      },
      {
        Sid       = "PassTaskRole"
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = "arn:aws:iam::${local.account}:role/${local.prefix}-task"
        Condition = { StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" } }
      },
      {
        Sid      = "TerminateTaskInstances"
        Effect   = "Allow"
        Action   = "ec2:TerminateInstances"
        Resource = "${local.ec2}:instance/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = var.project
            "aws:ResourceTag/Purpose" = "ci-task"
          }
        }
      },
      {
        # SendCommand is authorised against the document and each instance; the
        # AWS-owned document has no tags, so it gets its own statement.
        Sid      = "UseRunShellScript"
        Effect   = "Allow"
        Action   = "ssm:SendCommand"
        Resource = "arn:aws:ssm:${local.region}::document/AWS-RunShellScript"
      },
      {
        Sid      = "SendTaskCommands"
        Effect   = "Allow"
        Action   = "ssm:SendCommand"
        Resource = "${local.ec2}:instance/*"
        Condition = {
          StringEquals = {
            "ssm:resourceTag/Project" = var.project
            "ssm:resourceTag/Purpose" = "ci-task"
          }
        }
      },
      {
        Sid    = "ReadTaskOutput"
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          "logs:DescribeLogStreams",
          "s3:GetObject",
        ]
        Resource = [
          "arn:aws:logs:${local.region}:${local.account}:log-group:/${var.name_root}/${var.project}/tasks",
          "arn:aws:logs:${local.region}:${local.account}:log-group:/${var.name_root}/${var.project}/tasks:*",
          "${local.bucket}/tasks/*",
        ]
      },
      {
        Sid       = "ListTaskOutput"
        Effect    = "Allow"
        Action    = "s3:ListBucket"
        Resource  = local.bucket
        Condition = { StringLike = { "s3:prefix" = "tasks/*" } }
      },
      {
        # Gap: no resource-level support. Finds the template, the subnets and
        # the task instances, and checks the instance's agent is online.
        Sid    = "DescribeTasks"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeSubnets",
          "ec2:DescribeLaunchTemplates",
          "ssm:DescribeInstanceInformation",
        ]
        Resource = "*"
      },
      {
        # Gap: no resource-level support. Status and exit code of the task.
        Sid    = "FollowCommands"
        Effect = "Allow"
        Action = [
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations",
        ]
        Resource = "*"
      },
    ]
  }
}

resource "aws_iam_policy" "this" {
  name        = var.name
  description = "CI policy task/launch: launch the project's task instances from its launch template, run tasks on them, read their output and terminate them"
  policy      = jsonencode(local.policy)

  tags = {
    Component = "ci"
  }
}
