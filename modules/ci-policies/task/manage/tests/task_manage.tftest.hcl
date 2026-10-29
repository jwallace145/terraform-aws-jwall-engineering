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
  name    = "jwall-engineering-rusty-chess-ci-apply-task-manage"
  project = "rusty-chess"
}

run "launch_templates_by_project_tag" {
  command = plan

  assert {
    condition = (
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "CreateLaunchTemplate"][0].Action == "ec2:CreateLaunchTemplate" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "CreateLaunchTemplate"][0].Condition.StringEquals["aws:RequestTag/Project"] == "rusty-chess" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ManageLaunchTemplate"][0].Condition.StringEquals["aws:ResourceTag/Project"] == "rusty-chess" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ManageLaunchTemplate"][0].Resource == "arn:aws:ec2:us-east-1:123456789012:launch-template/*"
    )
    error_message = "launch templates are created and changed only with the project's tag"
  }

  assert {
    condition     = [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "TagLaunchTemplateOnCreate"][0].Condition.StringEquals["ec2:CreateAction"] == "CreateLaunchTemplate"
    error_message = "tags on a new launch template come with its creation"
  }
}

run "results_bucket_configuration_only" {
  command = plan

  assert {
    condition     = [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ManageTaskBucket"][0].Resource == "arn:aws:s3:::jwall-engineering-rusty-chess-tasks"
    error_message = "the results bucket only"
  }

  assert {
    condition     = !anytrue([for a in flatten([for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Action]))]) : can(regex("^s3:.*Object", a))])
    error_message = "never its objects"
  }
}

run "wildcards_are_known_gaps" {
  command = plan

  assert {
    condition     = jsonencode(sort([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Sid if s.Resource == "*"])) == jsonencode(["TagLaunchTemplateOnCreate"])
    error_message = "only the documented gaps may use Resource = *"
  }
}

# `description` forces replacement of the policy; it is frozen.
run "description_is_frozen" {
  command = plan

  assert {
    condition     = aws_iam_policy.this.description == "CI policy task/manage: create and manage the project's task launch template and task results bucket"
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
