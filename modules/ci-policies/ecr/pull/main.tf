locals {
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
        Sid    = "PullImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
        ]
        Resource = var.repository_arn
      },
    ]
  }
}

resource "aws_iam_policy" "this" {
  name        = var.name
  description = "CI policy ecr/pull: log in to ECR and pull images from one repository"
  policy      = jsonencode(local.policy)

  tags = {
    Component = "ci"
  }
}
