locals {
  bucket_arns = [for b in var.bucket_names : "arn:aws:s3:::${b}"]

  # Write-only: pair with dataset/read. The writers' inline policies are
  # written through container/manage, whose role scoping already covers them.
  policy = {
    Version = "2012-10-17"
    Statement = [
      {
        # Bucket configuration only; never its objects. DeleteBucket succeeds
        # only on an empty bucket, and the module refuses to destroy it.
        Sid    = "ManageDatasetBuckets"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:PutEncryptionConfiguration",
          "s3:PutLifecycleConfiguration",
          "s3:PutBucketPublicAccessBlock",
          "s3:PutBucketOwnershipControls",
          "s3:PutBucketTagging",
        ]
        Resource = local.bucket_arns
      },
    ]
  }
}

resource "aws_iam_policy" "this" {
  name        = var.name
  description = "CI policy dataset/manage: create and configure the project's dataset buckets"
  policy      = jsonencode(local.policy)

  tags = {
    Component = "ci"
  }
}
