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
  name    = "jwall-engineering-rusty-chess-ci-apply-container-manage"
  project = "rusty-chess"
}

run "ec2_creates_require_project_tag" {
  command = plan

  assert {
    condition = (
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "CreateProjectNetwork"][0].Condition.StringEquals["aws:RequestTag/Project"] == "rusty-chess" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "RunProjectInstances"][0].Condition.StringEquals["aws:RequestTag/Project"] == "rusty-chess"
    )
    error_message = "EC2 create actions must require the Project tag on the new resource"
  }
}

run "ec2_changes_require_project_tag" {
  command = plan

  assert {
    condition = (
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ManageProjectNetwork"][0].Condition.StringEquals["aws:ResourceTag/Project"] == "rusty-chess" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ManageProjectInstances"][0].Condition.StringEquals["aws:ResourceTag/Project"] == "rusty-chess" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "CreateInsideProjectVpc"][0].Condition.StringEquals["aws:ResourceTag/Project"] == "rusty-chess"
    )
    error_message = "EC2 change actions must require the Project tag on the existing resource"
  }
}

run "iam_is_bounded_by_name" {
  command = plan

  assert {
    condition = alltrue([
      for r in flatten([[for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ManageProjectRoles"][0].Resource]) :
      can(regex("^arn:aws:iam::123456789012:(role|instance-profile|policy)/jwall-engineering-rusty-chess-", r))
    ])
    error_message = "ManageProjectRoles must be bounded to <name_root>-<project>-* roles, instance profiles and policies"
  }

  assert {
    condition = (
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "PassInstanceRole"][0].Condition.StringEquals["iam:PassedToService"] == "ec2.amazonaws.com" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "PassInstanceRole"][0].Resource == "arn:aws:iam::123456789012:role/jwall-engineering-rusty-chess-*"
    )
    error_message = "PassRole must be limited to project roles handed to EC2"
  }

  assert {
    condition = jsonencode([for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "AttachProjectRolePolicies"][0].Condition.ArnLike["iam:PolicyARN"]) == jsonencode([
      "arn:aws:iam::123456789012:policy/jwall-engineering-rusty-chess-*",
      "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    ])
    error_message = "AttachRolePolicy must be bounded by the allow-list of attachable policies"
  }
}

run "attachable_policy_arns_extend_the_allow_list" {
  command = plan

  variables {
    attachable_policy_arns = ["arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"]
  }

  assert {
    condition     = contains([for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "AttachProjectRolePolicies"][0].Condition.ArnLike["iam:PolicyARN"], "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy")
    error_message = "attachable_policy_arns must extend the allow-list"
  }
}

run "no_iam_wildcards" {
  command = plan

  assert {
    condition = !anytrue([
      for a in flatten([for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Action]))]) :
      a == "*" || a == "iam:*" || (startswith(a, "iam:") && endswith(a, "*"))
    ])
    error_message = "no wildcard IAM actions"
  }
}

run "wildcards_are_known_gaps" {
  command = plan

  assert {
    condition     = sort([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Sid if s.Resource == "*"]) == tolist(["CreateTagsOnCreate", "ManageProjectTags"])
    error_message = "only the two tag statements may use Resource = *"
  }
}

run "records_bucket_is_bounded" {
  command = plan

  assert {
    condition     = [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ManageRecordsBucket"][0].Resource == "arn:aws:s3:::jwall-engineering-rusty-chess-records"
    error_message = "ManageRecordsBucket must name only the records bucket"
  }

  assert {
    condition     = !anytrue([for a in flatten([for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Action]))]) : can(regex("^s3:.*Object", a))])
    error_message = "the apply role never touches objects"
  }
}

run "image_repository_is_bounded" {
  command = plan

  assert {
    condition = alltrue([
      for r in flatten([[for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ManageProjectImageRepository"][0].Resource]) :
      startswith(r, "arn:aws:ecr:us-east-1:123456789012:repository/jwall-engineering-rusty-chess")
    ])
    error_message = "ManageProjectImageRepository must be bounded to the project's repository"
  }

  assert {
    condition     = contains(flatten([for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Action]))]), "ecr:CreateRepository")
    error_message = "the apply role creates the repository"
  }
}

run "no_secret_parameter_writes" {
  command = plan

  assert {
    condition     = !anytrue([for a in flatten([for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Action]))]) : a == "ssm:PutParameter" || a == "ssm:DeleteParameter"])
    error_message = "the apply role never writes parameter values; the secret is written by the owner only"
  }
}

# `description` forces replacement of the policy, which would detach it from
# every role mid-apply. It is frozen; change the README instead.
run "description_is_frozen" {
  command = plan

  assert {
    condition     = aws_iam_policy.this.description == "CI policy container/manage: create and manage the project's network, instance, instance role, image repository, parameters, log group and records bucket"
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

# The egress rule resource (aws_vpc_security_group_egress_rule) is created
# with tags: AuthorizeSecurityGroupEgress authorises the new
# security-group-rule with aws:RequestTag and needs ec2:CreateTags for that
# create action.
run "security_group_rules_can_be_created_with_tags" {
  command = plan

  assert {
    condition = (
      contains([for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "CreateProjectSecurityGroupRules"][0].Action, "ec2:AuthorizeSecurityGroupEgress") &&
      contains([for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "CreateProjectSecurityGroupRules"][0].Action, "ec2:AuthorizeSecurityGroupIngress") &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "CreateProjectSecurityGroupRules"][0].Resource == "arn:aws:ec2:us-east-1:123456789012:security-group-rule/*" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "CreateProjectSecurityGroupRules"][0].Condition.StringEquals["aws:RequestTag/Project"] == "rusty-chess"
    )
    error_message = "new security group rules are authorised by their request tags"
  }

  assert {
    condition = (
      contains([for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "CreateTagsOnCreate"][0].Condition.StringEquals["ec2:CreateAction"], "AuthorizeSecurityGroupEgress") &&
      contains([for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "CreateTagsOnCreate"][0].Condition.StringEquals["ec2:CreateAction"], "AuthorizeSecurityGroupIngress")
    )
    error_message = "tagging a rule on creation is allowed for the Authorize actions"
  }
}
