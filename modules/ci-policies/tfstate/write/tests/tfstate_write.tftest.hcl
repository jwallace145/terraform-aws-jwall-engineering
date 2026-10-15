mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  name       = "jwall-engineering-infra-ci-apply-tfstate-write"
  bucket_arn = "arn:aws:s3:::jwall-engineering-tfstate"
  key        = "project=infra/env=prod/infra-prod.tfstate"
}

run "key_scopes_to_one_object" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_policy.this.policy).Statement == [
      {
        Sid       = "ListState"
        Effect    = "Allow"
        Action    = "s3:ListBucket"
        Resource  = "arn:aws:s3:::jwall-engineering-tfstate"
        Condition = { StringLike = { "s3:prefix" = "project=infra/env=prod/infra-prod.tfstate*" } }
      },
      {
        Sid      = "ReadWriteState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
        Resource = "arn:aws:s3:::jwall-engineering-tfstate/project=infra/env=prod/infra-prod.tfstate"
      },
      {
        Sid      = "LockState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::jwall-engineering-tfstate/project=infra/env=prod/infra-prod.tfstate.tflock"
      },
    ]
    error_message = "with key, the policy reads and writes one object and manages its lock"
  }
}

run "prefix_never_deletes_state" {
  command = plan

  variables {
    key    = null
    prefix = "project=guitar/"
  }

  assert {
    condition = (
      jsondecode(aws_iam_policy.this.policy).Statement[1].Resource == "arn:aws:s3:::jwall-engineering-tfstate/project=guitar/*" &&
      !contains(jsondecode(aws_iam_policy.this.policy).Statement[1].Action, "s3:DeleteObject") &&
      jsondecode(aws_iam_policy.this.policy).Statement[2].Resource == "arn:aws:s3:::jwall-engineering-tfstate/project=guitar/*.tflock"
    )
    error_message = "with prefix, state objects are written but only locks are deleted"
  }
}

run "rejects_both_key_and_prefix" {
  command = plan

  variables {
    prefix = "project=infra/"
  }

  expect_failures = [var.key]
}
