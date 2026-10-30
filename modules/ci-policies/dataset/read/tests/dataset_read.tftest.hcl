mock_provider "aws" {
  override_during = plan
}

variables {
  name         = "jwall-engineering-rusty-chess-ci-plan-dataset-read"
  project      = "rusty-chess"
  bucket_names = ["jwall-engineering-rusty-chess-nnue"]
}

run "reads_only_the_dataset_buckets" {
  command = plan

  assert {
    condition     = [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ReadDatasetBuckets"][0].Resource == ["arn:aws:s3:::jwall-engineering-rusty-chess-nnue"]
    error_message = "the dataset buckets' configuration only"
  }

  assert {
    condition     = contains([for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ReadDatasetBuckets"][0].Action, "s3:GetReplicationConfiguration")
    error_message = "aws_s3_bucket refresh reads the replication configuration"
  }
}

run "no_writes_and_no_objects" {
  command = plan

  assert {
    condition = alltrue([
      for a in flatten([for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Action]))]) :
      can(regex("^(s3:Get|s3:ListBucket$)", a)) && !can(regex("^s3:GetObject", a))
    ])
    error_message = "read-only, and never the data itself"
  }
}

run "rejects_buckets_of_other_projects" {
  command = plan

  variables {
    bucket_names = ["jwall-engineering-other-nnue"]
  }

  expect_failures = [var.bucket_names]
}

run "rejects_no_buckets" {
  command = plan

  variables {
    bucket_names = []
  }

  expect_failures = [var.bucket_names]
}

# `description` forces replacement of the policy; it is frozen.
run "description_is_frozen" {
  command = plan

  assert {
    condition     = aws_iam_policy.this.description == "CI policy dataset/read: read the configuration of the project's dataset buckets"
    error_message = "the policy description must never change: it forces replacement"
  }
}
