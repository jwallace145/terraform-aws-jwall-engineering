data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  prefix     = "${var.name_root}-${var.project}"

  # Everything a release needs and nothing else: push the image, set the
  # desired version, ask the instance to reconcile and follow it.
  policy = {
    Version = "2012-10-17"
    Statement = [
      {
        # Docker login. The action has no resource-level support.
        Sid      = "GetEcrAuthorizationToken"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        # DescribeImages lets the CLI refuse to overwrite an existing tag
        # before pushing (the repository's immutability is the backstop).
        Sid    = "PushImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeImages",
        ]
        Resource = "arn:aws:ecr:${local.region}:${local.account_id}:repository/${local.prefix}"
      },
      {
        # The bot's own parameters only. The secret lives outside bot/ and
        # is never reachable.
        Sid    = "WriteDesiredVersion"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:AddTagsToResource",
        ]
        Resource = "arn:aws:ssm:${local.region}:${local.account_id}:parameter/${var.name_root}/${var.project}/bot/*"
      },
      {
        Sid    = "SendReconcileCommand"
        Effect = "Allow"
        Action = "ssm:SendCommand"
        Resource = [
          "arn:aws:ssm:${local.region}::document/AWS-RunShellScript",
          "arn:aws:ec2:${local.region}:${local.account_id}:instance/*",
        ]
        Condition = {
          StringEquals = {
            "ssm:resourceTag/Project" = var.project
          }
        }
      },
      {
        # Gap: command status actions have no resource-level support.
        Sid    = "FollowCommands"
        Effect = "Allow"
        Action = [
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations",
          "ssm:ListCommands",
        ]
        Resource = "*"
      },
      {
        # Gap: no resource-level support. How the CLI finds the instance by
        # its Project and Component tags and checks the agent is online.
        Sid    = "DescribeInstances"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ssm:DescribeInstanceInformation",
        ]
        Resource = "*"
      },
    ]
  }
}

resource "aws_iam_policy" "this" {
  name        = var.name
  description = "CI policy container/release: push images to the project's repository, set its desired version and run its reconciler"
  policy      = jsonencode(local.policy)

  tags = {
    Component = "ci"
  }
}
