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

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock"
    }
  }
}

variables {
  project           = "rusty-chess"
  repository        = "jwallace145/rusty-chess-v2"
  owner_id          = "35950238"
  repository_id     = "100"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  policies          = ["task/launch"]
  policy_inputs     = { task = { instance_types = ["c8a.xlarge", "c8a.2xlarge"] } }
}

run "role_identity" {
  command = plan

  assert {
    condition     = module.role.name == "jwall-engineering-rusty-chess-ci-task"
    error_message = "the role must be named <name_root>-<project>-ci-task"
  }

  assert {
    condition     = module.role.tags == tomap({ Component = "ci", Name = "jwall-engineering-rusty-chess-ci-task" })
    error_message = "the role must carry Component = ci and Name = <role name>"
  }

  assert {
    condition     = output.role_name == module.role.name && output.role_arn == module.role.arn
    error_message = "role_name and role_arn must expose the role"
  }
}

# GitHub issues no OIDC token to pull_request runs from forks, so trusting the
# repository's own pull_request subject admits same-repository PRs only.
run "trusts_pull_requests_and_main_only" {
  command = plan

  assert {
    condition = jsonencode(jsondecode(module.role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]) == jsonencode([
      "repo:jwallace145/rusty-chess-v2:pull_request",
      "repo:jwallace145/rusty-chess-v2:ref:refs/heads/main",
      "repo:jwallace145@35950238/rusty-chess-v2@100:pull_request",
      "repo:jwallace145@35950238/rusty-chess-v2@100:ref:refs/heads/main",
    ])
    error_message = "exactly the repository's pull requests and main, classic and immutable"
  }

  assert {
    condition = (
      !contains(keys(jsondecode(module.role.assume_role_policy).Statement[0].Condition), "StringLike") &&
      jsondecode(module.role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com" &&
      jsondecode(module.role.assume_role_policy).Statement[0].Sid == "GitHubTaskEvents"
    )
    error_message = "no glob subjects; audience pinned"
  }
}

run "policies_come_from_the_catalog" {
  command = plan

  assert {
    condition     = module.policies.names["task/launch"] == "jwall-engineering-rusty-chess-ci-task-task-launch"
    error_message = "the launch policy comes from ci-policies with role = task"
  }
}

run "rejects_wildcard_subject" {
  command = plan

  variables {
    subjects = ["ref:refs/heads/*"]
  }

  expect_failures = [var.subjects]
}

run "rejects_tag_subject" {
  command = plan

  variables {
    subjects = ["ref:refs/tags/v1"]
  }

  expect_failures = [var.subjects]
}

run "rejects_write_policies" {
  command = plan

  variables {
    policies = ["container/manage"]
  }

  expect_failures = [var.policies]
}

# `task run` holds the role for the whole task: up to task-runner.max_hours
# (at most 24) plus launch and setup. A one-hour session would expire mid-task
# and leave the CLI unable to stream, collect or terminate.
run "sessions_outlast_the_longest_task" {
  command = plan

  assert {
    condition     = module.role.max_session_duration == 25200
    error_message = "the default session must cover a 6-hour task plus setup: 7 hours"
  }
}

run "session_duration_follows_input" {
  command = plan

  variables {
    max_session_duration = 43200
  }

  assert {
    condition     = module.role.max_session_duration == 43200
    error_message = "max_session_duration is passed to the role"
  }
}

run "rejects_a_session_longer_than_iam_allows" {
  command = plan

  variables {
    max_session_duration = 43201
  }

  expect_failures = [var.max_session_duration]
}
