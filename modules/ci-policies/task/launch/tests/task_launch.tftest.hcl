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
  name           = "jwall-engineering-rusty-chess-ci-task-task-launch"
  project        = "rusty-chess"
  instance_types = ["c8a.xlarge", "c8a.2xlarge"]
}

# Every launch must come from a launch template tagged for the project's task
# runner: the instance statement requires the ec2:LaunchTemplate key, and the
# template statement requires the template's tags.
run "launches_only_from_the_project_template" {
  command = plan

  assert {
    condition = (
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "RunFromProjectTemplate"][0].Resource == "arn:aws:ec2:us-east-1:123456789012:launch-template/*" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "RunFromProjectTemplate"][0].Condition.StringEquals["aws:ResourceTag/Project"] == "rusty-chess" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "RunFromProjectTemplate"][0].Condition.StringEquals["aws:ResourceTag/Component"] == "task-runner"
    )
    error_message = "the template must carry the project's task-runner tags"
  }

  assert {
    condition = (
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "RunTaskInstances"][0].Resource == "arn:aws:ec2:us-east-1:123456789012:instance/*" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "RunTaskInstances"][0].Condition.ArnLike["ec2:LaunchTemplate"] == "arn:aws:ec2:us-east-1:123456789012:launch-template/*" &&
      jsonencode([for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "RunTaskInstances"][0].Condition.StringEquals["ec2:InstanceType"]) == jsonencode(["c8a.xlarge", "c8a.2xlarge"]) &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "RunTaskInstances"][0].Condition.StringEquals["aws:RequestTag/Project"] == "rusty-chess" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "RunTaskInstances"][0].Condition.StringEquals["aws:RequestTag/Purpose"] == "ci-task"
    )
    error_message = "instances: from a template, allow-listed types, tagged for the project's tasks"
  }

  assert {
    condition = (
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "RunTaskVolumes"][0].Condition.StringEquals["aws:RequestTag/Purpose"] == "ci-task" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "RunFromAmazonImages"][0].Resource == "arn:aws:ec2:us-east-1::image/*" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "RunFromAmazonImages"][0].Condition.StringEquals["ec2:Owner"] == "amazon"
    )
    error_message = "volumes are tagged; images are Amazon's own"
  }

  assert {
    condition = (
      jsonencode(sort([for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "RunInProjectNetwork"][0].Resource)) == jsonencode(sort(["arn:aws:ec2:us-east-1:123456789012:subnet/*", "arn:aws:ec2:us-east-1:123456789012:security-group/*"])) &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "RunInProjectNetwork"][0].Condition.StringEquals["aws:ResourceTag/Project"] == "rusty-chess"
    )
    error_message = "only the project's subnets and security groups"
  }

  assert {
    condition     = !anytrue([for r in flatten([for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Resource]))]) : strcontains(r, "key-pair")])
    error_message = "task instances have no SSH key"
  }
}

run "passes_only_the_task_role_to_ec2" {
  command = plan

  assert {
    condition = (
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "PassTaskRole"][0].Resource == "arn:aws:iam::123456789012:role/jwall-engineering-rusty-chess-task" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "PassTaskRole"][0].Condition.StringEquals["iam:PassedToService"] == "ec2.amazonaws.com"
    )
    error_message = "only the task instance role, only to EC2"
  }

  assert {
    condition     = !anytrue([for a in flatten([for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Action]))]) : startswith(a, "iam:") && a != "iam:PassRole"])
    error_message = "no other IAM action"
  }
}

run "touches_only_task_instances" {
  command = plan

  assert {
    condition = (
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "TerminateTaskInstances"][0].Condition.StringEquals["aws:ResourceTag/Purpose"] == "ci-task" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "TerminateTaskInstances"][0].Condition.StringEquals["aws:ResourceTag/Project"] == "rusty-chess" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "SendTaskCommands"][0].Condition.StringEquals["ssm:resourceTag/Purpose"] == "ci-task" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "SendTaskCommands"][0].Condition.StringEquals["ssm:resourceTag/Project"] == "rusty-chess" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "UseRunShellScript"][0].Resource == "arn:aws:ssm:us-east-1::document/AWS-RunShellScript"
    )
    error_message = "terminate and send commands only to the project's task instances (never the bot)"
  }

  assert {
    condition     = [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "TagOnLaunch"][0].Condition.StringEquals["ec2:CreateAction"] == "RunInstances"
    error_message = "tags only with the launch"
  }
}

run "reads_only_its_output" {
  command = plan

  assert {
    condition = (
      jsonencode([for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ReadTaskOutput"][0].Resource) == jsonencode([
        "arn:aws:logs:us-east-1:123456789012:log-group:/jwall-engineering/rusty-chess/tasks",
        "arn:aws:logs:us-east-1:123456789012:log-group:/jwall-engineering/rusty-chess/tasks:*",
        "arn:aws:s3:::jwall-engineering-rusty-chess-tasks/tasks/*",
      ]) &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ListTaskOutput"][0].Condition.StringLike["s3:prefix"] == "tasks/*"
    )
    error_message = "the task log group and the task results prefix only"
  }

  assert {
    condition     = !anytrue([for a in flatten([for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Action]))]) : contains(["s3:PutObject", "s3:DeleteObject", "ec2:CreateLaunchTemplate", "ec2:ModifyLaunchTemplate"], a)])
    error_message = "the launch role writes no results and changes no template"
  }
}

run "wildcards_are_known_gaps" {
  command = plan

  assert {
    condition     = jsonencode(sort([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Sid if s.Resource == "*"])) == jsonencode(["DescribeTasks", "FollowCommands"])
    error_message = "only the documented gaps may use Resource = *"
  }
}

run "description_is_frozen" {
  command = plan

  assert {
    condition     = aws_iam_policy.this.description == "CI policy task/launch: launch the project's task instances from its launch template, run tasks on them, read their output and terminate them"
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

run "rejects_no_instance_types" {
  command = plan

  variables {
    instance_types = []
  }

  expect_failures = [var.instance_types]
}
