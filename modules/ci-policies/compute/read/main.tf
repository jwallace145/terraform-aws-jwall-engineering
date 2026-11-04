data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  prefix     = "${var.name_root}-${var.project}"

  iam_arns = [
    "arn:aws:iam::${local.account_id}:role/${local.prefix}-*",
    "arn:aws:iam::${local.account_id}:instance-profile/${local.prefix}-*",
    "arn:aws:iam::${local.account_id}:policy/${local.prefix}-*",
  ]
  log_group_arns = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:/${var.name_root}/${var.project}/*"]
  ami_parameters = "arn:aws:ssm:${local.region}::parameter/aws/service/ami-amazon-linux-latest/*"

  # Read-only: pair with compute/manage, which the apply role also needs
  # for refresh. The statements are copied from container/read, for projects
  # with no bot; a test in ci-policies keeps them equal.
  policy = {
    Version = "2012-10-17"
    Statement = [
      {
        # Gap: EC2 describe actions have no resource-level support. They
        # disclose metadata about every VPC and instance in the account.
        Sid      = "DescribeEc2"
        Effect   = "Allow"
        Action   = "ec2:Describe*"
        Resource = "*"
      },
      {
        # The AMI lookup: public parameters live in no account.
        Sid    = "ReadPublicAmiParameters"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
        ]
        Resource = local.ami_parameters
      },
      {
        Sid    = "ReadProjectRoles"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:GetInstanceProfile",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
        ]
        Resource = local.iam_arns
      },
      {
        # Gap: no resource-level support. Lists log group names only.
        Sid      = "DescribeLogGroups"
        Effect   = "Allow"
        Action   = "logs:DescribeLogGroups"
        Resource = "*"
      },
      {
        Sid    = "ReadProjectLogGroups"
        Effect = "Allow"
        Action = [
          "logs:ListTagsForResource",
          "logs:DescribeSubscriptionFilters",
          "logs:DescribeMetricFilters",
          "logs:DescribeLogStreams",
          "logs:FilterLogEvents",
          "logs:GetLogEvents",
        ]
        Resource = local.log_group_arns
      },
    ]
  }
}

resource "aws_iam_policy" "this" {
  name        = var.name
  description = "CI policy compute/read: read the project's network, instance role and log groups"
  policy      = jsonencode(local.policy)

  tags = {
    Component = "ci"
  }
}
