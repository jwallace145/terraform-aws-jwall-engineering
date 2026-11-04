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
  name    = "jwall-engineering-tawe-ci-apply-compute-manage"
  project = "tawe"
}

run "has_exactly_the_compute_statements" {
  command = plan

  assert {
    condition = jsonencode(sort([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Sid])) == jsonencode([
      "CreateInsideProjectVpc",
      "CreateProjectNetwork",
      "CreateProjectSecurityGroupRules",
      "CreateTagsOnCreate",
      "ManageProjectLogGroups",
      "ManageProjectNetwork",
      "ManageProjectRoles",
      "ManageProjectTags",
      "PassInstanceRole",
    ])
    error_message = "compute/manage holds only the network, instance role and log group writes"
  }
}

run "ec2_is_bounded_by_the_project_tag" {
  command = plan

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_policy.this.policy).Statement :
      s.Condition.StringEquals["aws:RequestTag/Project"] == "tawe"
      if contains(["CreateProjectNetwork", "CreateProjectSecurityGroupRules"], s.Sid)
    ])
    error_message = "EC2 create actions must require the Project tag on the new resource"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_policy.this.policy).Statement :
      s.Condition.StringEquals["aws:ResourceTag/Project"] == "tawe"
      if contains(["CreateInsideProjectVpc", "ManageProjectNetwork", "ManageProjectTags"], s.Sid)
    ])
    error_message = "EC2 change actions must require the Project tag on the existing resource"
  }
}

run "tags_on_create_are_bounded_to_this_policys_create_calls" {
  command = plan

  assert {
    condition = jsonencode(sort(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Condition.StringEquals["ec2:CreateAction"] if s.Sid == "CreateTagsOnCreate"]))) == jsonencode(sort([
      "CreateVpc",
      "CreateSubnet",
      "CreateInternetGateway",
      "CreateRouteTable",
      "CreateSecurityGroup",
      "AuthorizeSecurityGroupEgress",
      "AuthorizeSecurityGroupIngress",
    ]))
    error_message = "CreateTagsOnCreate must be bounded to the create calls this policy allows, without RunInstances"
  }
}

run "iam_and_logs_are_bounded_by_name" {
  command = plan

  assert {
    condition = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "ManageProjectRoles"])) == jsonencode([
      "arn:aws:iam::123456789012:role/jwall-engineering-tawe-*",
      "arn:aws:iam::123456789012:instance-profile/jwall-engineering-tawe-*",
      "arn:aws:iam::123456789012:policy/jwall-engineering-tawe-*",
    ])
    error_message = "ManageProjectRoles must keep its <name_root>-<project>-* name scoping"
  }

  assert {
    condition = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : { r = s.Resource, c = s.Condition } if s.Sid == "PassInstanceRole"])) == jsonencode({
      r = "arn:aws:iam::123456789012:role/jwall-engineering-tawe-*"
      c = { StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" } }
    })
    error_message = "PassRole must be limited to project roles handed to EC2"
  }

  assert {
    condition = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "ManageProjectLogGroups"])) == jsonencode([
      "arn:aws:logs:us-east-1:123456789012:log-group:/jwall-engineering/tawe/*",
    ])
    error_message = "ManageProjectLogGroups must be bounded to the project's log groups"
  }
}

run "wildcards_are_known_gaps" {
  command = plan

  assert {
    condition     = jsonencode(sort([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Sid if s.Resource == "*"])) == jsonencode(["CreateTagsOnCreate", "ManageProjectTags"])
    error_message = "only the two tag statements may use Resource = *"
  }
}

run "nothing_a_project_without_a_bot_does_not_need" {
  command = plan

  assert {
    condition = !anytrue([
      for a in flatten([for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Action]))]) :
      can(regex("^(ecr:|s3:|ssm:Put)", a)) || contains(["ec2:RunInstances", "ec2:TerminateInstances"], a)
    ])
    error_message = "compute/manage grants no image repository, bucket, parameter write or instance action"
  }
}

# Nothing it manages attaches a managed policy: the task instance role's policy
# is inline. Attaching is what the allow-list in container/manage bounds.
run "attaches_no_managed_policies" {
  command = plan

  assert {
    condition     = !contains(flatten([for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Action]))]), "iam:AttachRolePolicy")
    error_message = "compute/manage must not attach managed policies to roles"
  }
}

# `description` forces replacement of the policy, which would detach it from
# every role mid-apply. It is frozen; change the README instead.
run "description_is_frozen" {
  command = plan

  assert {
    condition     = aws_iam_policy.this.description == "CI policy compute/manage: create and manage the project's network, instance role and log groups"
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
