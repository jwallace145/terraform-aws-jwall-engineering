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
  name    = "jwall-engineering-tawe-ci-plan-compute-read"
  project = "tawe"
}

run "has_exactly_the_compute_statements" {
  command = plan

  assert {
    condition = jsonencode(sort([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Sid])) == jsonencode([
      "DescribeEc2",
      "DescribeLogGroups",
      "ReadProjectLogGroups",
      "ReadProjectRoles",
      "ReadPublicAmiParameters",
    ])
    error_message = "compute/read holds only the network, instance role and log group reads"
  }
}

run "scoped_resources" {
  command = plan

  assert {
    condition = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "ReadProjectRoles"])) == jsonencode([
      "arn:aws:iam::123456789012:role/jwall-engineering-tawe-*",
      "arn:aws:iam::123456789012:instance-profile/jwall-engineering-tawe-*",
      "arn:aws:iam::123456789012:policy/jwall-engineering-tawe-*",
    ])
    error_message = "ReadProjectRoles must keep its <name_root>-<project>-* name scoping"
  }

  assert {
    condition = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "ReadProjectLogGroups"])) == jsonencode([
      "arn:aws:logs:us-east-1:123456789012:log-group:/jwall-engineering/tawe/*",
    ])
    error_message = "ReadProjectLogGroups must be bounded to the project's log groups"
  }

  assert {
    condition     = one([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "ReadPublicAmiParameters"]) == "arn:aws:ssm:us-east-1::parameter/aws/service/ami-amazon-linux-latest/*"
    error_message = "ReadPublicAmiParameters must name only the public Amazon Linux AMI parameters"
  }
}

run "wildcards_are_known_gaps" {
  command = plan

  assert {
    condition     = jsonencode(sort([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Sid if s.Resource == "*"])) == jsonencode(["DescribeEc2", "DescribeLogGroups"])
    error_message = "only the documented describe actions may use Resource = *"
  }
}

run "nothing_a_project_without_a_bot_does_not_need" {
  command = plan

  assert {
    condition = !anytrue([
      for a in flatten([for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Action]))]) :
      can(regex("^(ecr:|s3:|ssm:Put)", a)) || contains(["ec2:RunInstances", "ec2:TerminateInstances"], a)
    ])
    error_message = "compute/read grants no image repository, bucket, parameter write or instance action"
  }
}

# `description` forces replacement of the policy, which would detach it from
# every role mid-apply. It is frozen; change the README instead.
run "description_is_frozen" {
  command = plan

  assert {
    condition     = aws_iam_policy.this.description == "CI policy compute/read: read the project's network, instance role and log groups"
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
