mock_provider "aws" {
  override_during = plan
}

variables {
  name         = "jwall-engineering-rusty-chess-ci-apply-dataset-manage"
  project      = "rusty-chess"
  bucket_names = ["jwall-engineering-rusty-chess-nnue"]
}

run "dataset_bucket_configuration_only" {
  command = plan

  assert {
    condition     = [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ManageDatasetBuckets"][0].Resource == ["arn:aws:s3:::jwall-engineering-rusty-chess-nnue"]
    error_message = "the dataset buckets only"
  }

  assert {
    condition     = !anytrue([for a in flatten([for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Action]))]) : can(regex("^s3:.*Object", a))])
    error_message = "never their objects: CI cannot write, read or delete the data"
  }

  assert {
    condition = alltrue([
      for a in ["s3:CreateBucket", "s3:PutBucketPolicy", "s3:PutEncryptionConfiguration", "s3:PutLifecycleConfiguration", "s3:PutBucketPublicAccessBlock", "s3:PutBucketOwnershipControls", "s3:PutBucketTagging"] :
      contains([for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ManageDatasetBuckets"][0].Action, a)
    ])
    error_message = "everything the dataset-bucket module configures"
  }
}

run "wildcards_are_known_gaps" {
  command = plan

  assert {
    condition     = jsonencode(sort([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Sid if s.Resource == "*"])) == jsonencode([])
    error_message = "no Resource = *"
  }
}

run "rejects_buckets_of_other_projects" {
  command = plan

  variables {
    bucket_names = ["jwall-engineering-rusty-chess-nnue", "someone-elses-bucket"]
  }

  expect_failures = [var.bucket_names]
}

# `description` forces replacement of the policy; it is frozen.
run "description_is_frozen" {
  command = plan

  assert {
    condition     = aws_iam_policy.this.description == "CI policy dataset/manage: create and configure the project's dataset buckets"
    error_message = "the policy description must never change: it forces replacement"
  }
}
