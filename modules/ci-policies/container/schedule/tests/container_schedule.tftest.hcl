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
  name    = "jwall-engineering-rusty-chess-ci-apply-container-schedule"
  project = "rusty-chess"
}

run "schedules_are_bounded_by_name" {
  command = plan

  assert {
    condition = [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ManageProjectSchedules"][0] == {
      Sid      = "ManageProjectSchedules"
      Effect   = "Allow"
      Action   = ["scheduler:CreateSchedule", "scheduler:UpdateSchedule", "scheduler:DeleteSchedule"]
      Resource = "arn:aws:scheduler:us-east-1:123456789012:schedule/default/jwall-engineering-rusty-chess-*"
    }
    error_message = "the apply role may create, update and delete only the project's schedules"
  }
}

run "scheduler_role_passes_only_to_eventbridge_scheduler" {
  command = plan

  assert {
    condition = [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "PassSchedulerRole"][0] == {
      Sid       = "PassSchedulerRole"
      Effect    = "Allow"
      Action    = "iam:PassRole"
      Resource  = "arn:aws:iam::123456789012:role/jwall-engineering-rusty-chess-*-scheduler"
      Condition = { StringEquals = { "iam:PassedToService" = "scheduler.amazonaws.com" } }
    }
    error_message = "only the project's *-scheduler roles, and only to scheduler.amazonaws.com"
  }
}

run "grants_nothing_else" {
  command = plan

  assert {
    condition     = sort([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Sid]) == tolist(["ManageProjectSchedules", "PassSchedulerRole"])
    error_message = "the policy is exactly the two statements"
  }
  assert {
    condition     = !anytrue([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource == "*"])
    error_message = "no statement is unscoped"
  }
}

run "description_is_frozen" {
  command = plan

  assert {
    condition     = aws_iam_policy.this.description == "CI policy container/schedule: manage the start, drain and stop schedules of the project's instance and pass their role to EventBridge Scheduler"
    error_message = "changing a policy description replaces the policy; keep it"
  }
}
