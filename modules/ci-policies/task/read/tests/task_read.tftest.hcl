mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }
}

variables {
  name    = "jwall-engineering-rusty-chess-ci-plan-task-read"
  project = "rusty-chess"
}

run "reads_only_the_task_resources" {
  command = plan

  assert {
    condition     = [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ReadTaskBucket"][0].Resource == "arn:aws:s3:::jwall-engineering-rusty-chess-tasks"
    error_message = "the results bucket's configuration only"
  }

  assert {
    condition     = contains([for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ReadTaskBucket"][0].Action, "s3:GetReplicationConfiguration")
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
    error_message = "read-only, and never the task results themselves"
  }
}

run "wildcards_are_known_gaps" {
  command = plan

  assert {
    condition     = jsonencode(sort([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Sid if s.Resource == "*"])) == jsonencode([])
    error_message = "only the documented gaps may use Resource = *"
  }
}

# `description` forces replacement of the policy; it is frozen.
run "description_is_frozen" {
  command = plan

  assert {
    condition     = aws_iam_policy.this.description == "CI policy task/read: read the configuration of the project's task results bucket"
    error_message = "the policy description must never change: it forces replacement"
  }
}

run "fits_policy_size_limit" {
  command = plan

  assert {
    condition     = length(aws_iam_policy.this.policy) <= 6144
    error_message = "managed policies are limited to 6144 characters"
  }
}
