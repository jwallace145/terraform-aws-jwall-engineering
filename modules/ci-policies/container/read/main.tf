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
  repository_arns = [
    "arn:aws:ecr:${local.region}:${local.account_id}:repository/${local.prefix}",
    "arn:aws:ecr:${local.region}:${local.account_id}:repository/${local.prefix}/*",
  ]
  parameter_arn  = "arn:aws:ssm:${local.region}:${local.account_id}:parameter/${var.name_root}/${var.project}/*"
  log_group_arns = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:/${var.name_root}/${var.project}/*"]
  records_bucket = "arn:aws:s3:::${local.prefix}-records"
  ami_parameters = "arn:aws:ssm:${local.region}::parameter/aws/service/ami-amazon-linux-latest/*"

  # Read-only: pair with container/manage, which the apply role also needs
  # for refresh.
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
        Sid    = "ReadProjectImageRepository"
        Effect = "Allow"
        Action = [
          "ecr:DescribeRepositories",
          "ecr:ListTagsForResource",
          "ecr:GetRepositoryPolicy",
          "ecr:GetLifecyclePolicy",
          "ecr:DescribeImages",
          "ecr:ListImages",
        ]
        Resource = local.repository_arns
      },
      {
        Sid    = "ReadProjectParameters"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ssm:ListTagsForResource",
        ]
        Resource = local.parameter_arn
      },
      {
        # Gap: no resource-level support. Lists parameter names and types
        # only, never values.
        Sid      = "DescribeParameters"
        Effect   = "Allow"
        Action   = "ssm:DescribeParameters"
        Resource = "*"
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
      {
        # Bucket configuration only: the objects (game records) are never
        # readable by CI.
        Sid    = "ReadRecordsBucket"
        Effect = "Allow"
        Action = [
          "s3:GetBucket*",
          "s3:GetEncryptionConfiguration",
          "s3:GetLifecycleConfiguration",
          "s3:GetAccelerateConfiguration",
          "s3:GetReplicationConfiguration",
          "s3:ListBucket",
        ]
        Resource = local.records_bucket
      },
    ]
  }
}

resource "aws_iam_policy" "this" {
  name        = var.name
  description = "CI policy container/read: read the project's network, instance, instance role, image repository, parameters, log group and records bucket"
  policy      = jsonencode(local.policy)

  tags = {
    Component = "ci"
  }
}
