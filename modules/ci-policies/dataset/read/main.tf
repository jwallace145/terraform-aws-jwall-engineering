locals {
  bucket_arns = [for b in var.bucket_names : "arn:aws:s3:::${b}"]

  # Read-only, for plan and refresh. The writers' inline policies live on
  # roles already readable through container/read.
  policy = {
    Version = "2012-10-17"
    Statement = [
      {
        # Bucket configuration only: CI never reads the data.
        Sid    = "ReadDatasetBuckets"
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
    ]
  }
}

resource "aws_iam_policy" "this" {
  name        = var.name
  description = "CI policy dataset/read: read the configuration of the project's dataset buckets"
  policy      = jsonencode(local.policy)

  tags = {
    Component = "ci"
  }
}
