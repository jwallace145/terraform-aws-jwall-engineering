mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  name       = "jwall-engineering-guitar-ci-plan-tfstate-read"
  bucket_arn = "arn:aws:s3:::jwall-engineering-tfstate"
  prefix     = "project=guitar/"
}

run "prefix_scopes_to_the_project" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_policy.this.policy).Statement == [
      {
        Sid       = "ListState"
        Effect    = "Allow"
        Action    = "s3:ListBucket"
        Resource  = "arn:aws:s3:::jwall-engineering-tfstate"
        Condition = { StringLike = { "s3:prefix" = "project=guitar/*" } }
      },
      {
        Sid      = "ReadState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = ["arn:aws:s3:::jwall-engineering-tfstate/project=guitar/*"]
      },
      {
        Sid      = "LockState"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::jwall-engineering-tfstate/project=guitar/*.tflock"
      },
    ]
    error_message = "with prefix, the policy reads everything under it and writes only locks"
  }

  assert {
    condition     = aws_iam_policy.this.name == var.name && aws_iam_policy.this.tags == tomap({ Component = "ci" })
    error_message = "the policy must be named var.name and tagged Component = ci"
  }
}

run "key_scopes_to_one_object" {
  command = plan

  variables {
    prefix = null
    key    = "project=infra/env=prod/infra-prod.tfstate"
  }

  assert {
    condition = (
      jsondecode(aws_iam_policy.this.policy).Statement[1].Resource == [
        "arn:aws:s3:::jwall-engineering-tfstate/project=infra/env=prod/infra-prod.tfstate",
        "arn:aws:s3:::jwall-engineering-tfstate/project=infra/env=prod/infra-prod.tfstate.tflock",
      ] &&
      jsondecode(aws_iam_policy.this.policy).Statement[2].Resource == "arn:aws:s3:::jwall-engineering-tfstate/project=infra/env=prod/infra-prod.tfstate.tflock"
    )
    error_message = "with key, the policy reads the object and its lock and writes only the lock"
  }
}

run "rejects_both_key_and_prefix" {
  command = plan

  variables {
    key = "project=infra/env=prod/infra-prod.tfstate"
  }

  expect_failures = [var.key]
}

run "rejects_neither_key_nor_prefix" {
  command = plan

  variables {
    prefix = null
  }

  expect_failures = [var.key]
}

run "rejects_wildcard_prefix" {
  command = plan

  variables {
    prefix = "project=*/"
  }

  expect_failures = [var.prefix]
}
