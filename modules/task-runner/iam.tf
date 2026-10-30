resource "aws_iam_role" "this" {
  name        = local.name
  description = "Task instances of ${var.project}${local.profile_suffix}: run commands, write task logs and results"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      },
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "this" {
  name = "${local.name}-instance"
  role = aws_iam_role.this.id

  # A task runs pull request code, so the instance can only write: no read
  # of earlier results, no images, no parameters, no secrets. That is also
  # why AmazonSSMManagedInstanceCore is not attached: it grants
  # ssm:GetParameter on every parameter in the account, the bot's token
  # among them.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Run Command's CloudWatch output. The agent creates the group if
        # it is missing; here it always exists.
        Sid    = "WriteTaskLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
        ]
        Resource = [
          local.log_group_arn,
          "${local.log_group_arn}:*",
        ]
      },
      {
        # The agent checks that the group exists first. The action has no
        # narrower resource; it lists group names and settings, no events.
        Sid      = "FindTaskLogGroup"
        Effect   = "Allow"
        Action   = "logs:DescribeLogGroups"
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:*"
      },
      {
        Sid    = "WriteTaskResults"
        Effect = "Allow"
        Action = "s3:PutObject"
        # aws:userid of an EC2 role session is <role-id>:<instance-id>, so each
        # instance writes only its own prefix and cannot touch another task's.
        Resource = "arn:aws:s3:::${local.results_bucket}/${local.results_prefix}$${aws:userid}/*"
      },
      {
        # The SSM agent's registration and message channels, the part of
        # AmazonSSMManagedInstanceCore Run Command and Session Manager need.
        # None of these actions supports resource-level scoping.
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
      },
    ]
  })
}

resource "aws_iam_instance_profile" "this" {
  name = local.name
  role = aws_iam_role.this.name

  tags = local.tags
}
