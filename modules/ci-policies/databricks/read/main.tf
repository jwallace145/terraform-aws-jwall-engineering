data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  prefix     = "${var.name_root}-${var.project}"

  bucket_arns = [
    "arn:aws:s3:::${local.prefix}-databricks-root",
    "arn:aws:s3:::${local.prefix}-databricks-catalog",
  ]

  # Read-only, for plan and refresh, apart from the append-only event log.
  # EC2 describes and the <name_root>-<project>-* roles (the -databricks-
  # roles included) are read through compute/read, which the plan and apply
  # roles also hold.
  policy = {
    Version = "2012-10-17"
    Statement = [
      {
        # Bucket configuration only: CI never reads the data. ListBucket is
        # HeadBucket, which refresh calls; it lists keys, not contents.
        Sid    = "ReadDatabricksBuckets"
        Effect = "Allow"
        Action = [
          "s3:GetBucket*",
          "s3:GetEncryptionConfiguration",
          "s3:GetLifecycleConfiguration",
          "s3:GetAccelerateConfiguration",
          "s3:GetReplicationConfiguration",
          "s3:ListBucket",
        ]
        Resource = local.bucket_arns
      },
      {
        Sid      = "ReadSecret"
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = var.secret_parameter_arn
      },
      {
        # Parameter Store encrypts a SecureString with the parameter's ARN as
        # encryption context, so this decrypts that one parameter only.
        Sid      = "DecryptSecretThroughSsm"
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = "arn:aws:kms:${local.region}:${local.account_id}:key/*"
        Condition = {
          StringEquals = {
            "kms:EncryptionContext:PARAMETER_ARN" = var.secret_parameter_arn
            "kms:ViaService"                      = "ssm.us-east-1.amazonaws.com"
          }
        }
      },
      {
        # Append-only: no read, no delete.
        Sid      = "AppendEvents"
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = var.events_object_arn
      },
    ]
  }
}

resource "aws_iam_policy" "this" {
  name        = var.name
  description = "CI policy databricks/read: read the project's Databricks workspace infrastructure and the Databricks credential"
  policy      = jsonencode(local.policy)

  tags = {
    Component = "ci"
  }
}
