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
        Sid    = "PushImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
        ]
        Resource = var.repository_arn
      },
    ]
  }
}

resource "aws_iam_policy" "this" {
  name        = var.name
  description = "CI policy ecr/push: log in to ECR and push images to one repository"
  policy      = jsonencode(local.policy)

  tags = {
    Component = "ci"
  }
}
