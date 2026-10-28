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
  name    = "jwall-engineering-rusty-chess-ci-release-container-release"
  project = "rusty-chess"
}

run "pushes_to_one_repository" {
  command = plan

  assert {
    condition     = [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "PushImages"][0].Resource == "arn:aws:ecr:us-east-1:123456789012:repository/jwall-engineering-rusty-chess"
    error_message = "PushImages must name only the project's repository"
  }

  assert {
    condition = jsonencode(sort([for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "PushImages"][0].Action)) == jsonencode(sort([
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:DescribeImages",
    ]))
    error_message = "PushImages grants the ecr/push actions plus DescribeImages (to refuse overwriting a tag)"
  }

  assert {
    condition     = [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "GetEcrAuthorizationToken"][0].Resource == "*"
    error_message = "the Docker login token is needed"
  }
}

run "writes_only_bot_parameters" {
  command = plan

  assert {
    condition = (
      jsonencode(sort([for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "WriteDesiredVersion"][0].Action)) == jsonencode(sort(["ssm:PutParameter", "ssm:GetParameter", "ssm:GetParameters", "ssm:AddTagsToResource"])) &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "WriteDesiredVersion"][0].Resource == "arn:aws:ssm:us-east-1:123456789012:parameter/jwall-engineering/rusty-chess/bot/*"
    )
    error_message = "the release role writes only /<name_root>/<project>/bot/*"
  }

  assert {
    condition = !anytrue([
      for r in flatten([for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Resource]))]) :
      startswith(r, "arn:aws:ssm:") && !startswith(r, "arn:aws:ssm:us-east-1:123456789012:parameter/jwall-engineering/rusty-chess/bot/") && r != "arn:aws:ssm:us-east-1::document/AWS-RunShellScript"
    ])
    error_message = "no SSM resource outside the bot parameters and the run-shell document (the secret is never reachable)"
  }
}

run "runs_commands_on_project_instances_only" {
  command = plan

  # SendCommand is authorised against the document and every instance. The
  # AWS-owned document has no tags, so a resource-tag condition on it always
  # fails: the document and the instances need separate statements.
  assert {
    condition = (
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "UseRunShellScript"][0].Action == "ssm:SendCommand" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "UseRunShellScript"][0].Resource == "arn:aws:ssm:us-east-1::document/AWS-RunShellScript" &&
      !contains(keys([for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "UseRunShellScript"][0]), "Condition")
    )
    error_message = "the run-shell document is allowed without a tag condition"
  }

  assert {
    condition = (
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "SendCommandToProjectInstances"][0].Action == "ssm:SendCommand" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "SendCommandToProjectInstances"][0].Resource == "arn:aws:ec2:us-east-1:123456789012:instance/*" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "SendCommandToProjectInstances"][0].Condition.StringEquals["ssm:resourceTag/Project"] == "rusty-chess"
    )
    error_message = "commands may only reach instances tagged with the project"
  }
}

run "wildcards_are_known_gaps" {
  command = plan

  assert {
    condition     = sort([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Sid if s.Resource == "*"]) == tolist(["DescribeInstances", "FollowCommands", "GetEcrAuthorizationToken"])
    error_message = "only the documented actions may use Resource = *"
  }
}

run "no_management" {
  command = plan

  assert {
    condition = !anytrue([
      for a in flatten([for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Action]))]) :
      can(regex("Delete|Create(Repository|Role|Policy)|PutLifecycle|PutRegistry|PutImageTag|PutImageScanning|SetRepositoryPolicy|RunInstances|TerminateInstances|^iam:|^s3:", a))
    ])
    error_message = "the release role ships images and rolls them out; it manages nothing"
  }
}

# `description` forces replacement of the policy, which would detach it from
# every role mid-apply. It is frozen; change the README instead.
run "description_is_frozen" {
  command = plan

  assert {
    condition     = aws_iam_policy.this.description == "CI policy container/release: push images to the project's repository, set its desired version and run its reconciler"
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
