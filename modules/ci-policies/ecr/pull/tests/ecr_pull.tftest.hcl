mock_provider "aws" {
  override_during = plan
}

variables {
  name           = "jwall-engineering-infra-ci-plan-ecr-pull"
  repository_arn = "arn:aws:ecr:us-east-1:123456789012:repository/jwall-engineering-sites"
}

run "pull_only" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_policy.this.policy).Statement == [
      {
        Sid      = "GetEcrAuthorizationToken"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid      = "PullImages"
        Effect   = "Allow"
        Action   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
        Resource = "arn:aws:ecr:us-east-1:123456789012:repository/jwall-engineering-sites"
      },
    ]
    error_message = "ecr/pull must only log in and pull from the one repository"
  }

  assert {
    condition     = aws_iam_policy.this.name == var.name && aws_iam_policy.this.tags == tomap({ Component = "ci" })
    error_message = "the policy must be named var.name and tagged Component = ci"
  }
}

run "rejects_non_repository_arn" {
  command = plan

  variables {
    repository_arn = "arn:aws:s3:::jwall-engineering-sites"
  }

  expect_failures = [var.repository_arn]
}
