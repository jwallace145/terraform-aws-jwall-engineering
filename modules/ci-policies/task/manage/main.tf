data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  prefix          = "${var.name_root}-${var.project}"
  launch_template = "arn:aws:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:launch-template/*"

  # Write-only: pair with task/read and container/read. The task instance role,
  # instance profile, security group and log group are created through
  # container/manage, whose name, tag and path scoping already covers them.
  policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "CreateLaunchTemplate"
        Effect    = "Allow"
        Action    = "ec2:CreateLaunchTemplate"
        Resource  = local.launch_template
        Condition = { StringEquals = { "aws:RequestTag/Project" = var.project } }
      },
      {
        Sid    = "ManageLaunchTemplate"
        Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplateVersion",
          "ec2:ModifyLaunchTemplate",
          "ec2:DeleteLaunchTemplate",
          "ec2:DeleteLaunchTemplateVersions",
        ]
        Resource  = local.launch_template
        Condition = { StringEquals = { "aws:ResourceTag/Project" = var.project } }
      },
      {
        # Gap: tags applied by CreateLaunchTemplate; bounded to that create call,
        # which itself requires the Project tag.
        Sid       = "TagLaunchTemplateOnCreate"
        Effect    = "Allow"
        Action    = "ec2:CreateTags"
        Resource  = "*"
        Condition = { StringEquals = { "ec2:CreateAction" = "CreateLaunchTemplate" } }
      },
      {
        # Bucket configuration only; never its objects.
        Sid    = "ManageTaskBucket"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:PutBucketVersioning",
          "s3:PutEncryptionConfiguration",
          "s3:PutLifecycleConfiguration",
          "s3:PutBucketPublicAccessBlock",
          "s3:PutBucketOwnershipControls",
          "s3:PutBucketTagging",
        ]
        Resource = "arn:aws:s3:::${local.prefix}-tasks"
      },
    ]
  }
}

resource "aws_iam_policy" "this" {
  name        = var.name
  description = "CI policy task/manage: create and manage the project's task launch template and task results bucket"
  policy      = jsonencode(local.policy)

  tags = {
    Component = "ci"
  }
}
