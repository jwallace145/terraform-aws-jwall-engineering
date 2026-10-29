locals {
  prefix = "${var.name_root}-${var.project}"

  # Read-only, for plan and refresh. The task launch template, instance role,
  # security group and log group are already readable through container/read.
  policy = {
    Version = "2012-10-17"
    Statement = [
      {
        # Bucket configuration only: the task results themselves are never
        # readable by the plan or apply roles.
        Sid    = "ReadTaskBucket"
        Effect = "Allow"
        Action = [
          "s3:GetBucket*",
          "s3:GetEncryptionConfiguration",
          "s3:GetLifecycleConfiguration",
          "s3:GetAccelerateConfiguration",
          "s3:GetReplicationConfiguration",
          "s3:ListBucket",
        ]
        Resource = "arn:aws:s3:::${local.prefix}-tasks"
      },
    ]
  }
}

resource "aws_iam_policy" "this" {
  name        = var.name
  description = "CI policy task/read: read the configuration of the project's task results bucket"
  policy      = jsonencode(local.policy)

  tags = {
    Component = "ci"
  }
}
