locals {
  policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListPreviews"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = var.bucket_arn
        Condition = {
          StringLike = {
            "s3:prefix" = "previews/*"
          }
        }
      },
      {
        Sid    = "WritePreviews"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "${var.bucket_arn}/previews/*"
      },
    ]
  }
}

resource "aws_iam_policy" "this" {
  name        = var.name
  description = "CI policy static-site/previews: publish and remove pull request previews under previews/"
  policy      = jsonencode(local.policy)

  tags = {
    Component = "ci"
  }
}
