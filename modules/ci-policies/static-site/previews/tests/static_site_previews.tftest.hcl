mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  name       = "jwall-engineering-guitar-ci-preview-static-site-previews"
  bucket_arn = "arn:aws:s3:::jwall-engineering-guitar"
}

run "limited_to_previews" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_policy.this.policy).Statement == [
      {
        Sid       = "ListPreviews"
        Effect    = "Allow"
        Action    = "s3:ListBucket"
        Resource  = "arn:aws:s3:::jwall-engineering-guitar"
        Condition = { StringLike = { "s3:prefix" = "previews/*" } }
      },
      {
        Sid      = "WritePreviews"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::jwall-engineering-guitar/previews/*"
      },
    ]
    error_message = "static-site/previews must only list and write previews/"
  }
}

# `description` forces replacement of the policy, which would detach it from
# every role mid-apply. It is frozen; change the README instead.
run "description_is_frozen" {
  command = plan

  assert {
    condition     = aws_iam_policy.this.description == "CI policy static-site/previews: publish and remove pull request previews under previews/"
    error_message = "the policy description must never change: it forces replacement"
  }
}
