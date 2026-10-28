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
  name    = "jwall-engineering-rusty-chess-ci-plan-container-read"
  project = "rusty-chess"
}

run "scoped_resources" {
  command = plan

  assert {
    condition = alltrue([
      for r in flatten([[for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ReadProjectRoles"][0].Resource]) :
      can(regex("^arn:aws:iam::123456789012:(role|instance-profile|policy)/jwall-engineering-rusty-chess-", r))
    ])
    error_message = "ReadProjectRoles must be bounded to <name_root>-<project>-* roles, instance profiles and policies"
  }

  assert {
    condition = alltrue([
      for r in flatten([[for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ReadProjectImageRepository"][0].Resource]) :
      startswith(r, "arn:aws:ecr:us-east-1:123456789012:repository/jwall-engineering-rusty-chess")
    ])
    error_message = "ReadProjectImageRepository must be bounded to the project's repository"
  }

  assert {
    condition = alltrue([
      for r in flatten([[for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ReadProjectParameters"][0].Resource]) :
      startswith(r, "arn:aws:ssm:us-east-1:123456789012:parameter/jwall-engineering/rusty-chess/")
    ])
    error_message = "ReadProjectParameters must be bounded to the project's parameter path"
  }

  assert {
    condition = alltrue([
      for r in flatten([[for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ReadProjectLogGroups"][0].Resource]) :
      startswith(r, "arn:aws:logs:us-east-1:123456789012:log-group:/jwall-engineering/rusty-chess/")
    ])
    error_message = "ReadProjectLogGroups must be bounded to the project's log groups"
  }

  assert {
    condition = alltrue([
      for r in flatten([[for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ReadRecordsBucket"][0].Resource]) :
      r == "arn:aws:s3:::jwall-engineering-rusty-chess-records"
    ])
    error_message = "ReadRecordsBucket must name only the records bucket"
  }

  assert {
    condition = alltrue([
      for r in flatten([[for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ReadPublicAmiParameters"][0].Resource]) :
      r == "arn:aws:ssm:us-east-1::parameter/aws/service/ami-amazon-linux-latest/*"
    ])
    error_message = "ReadPublicAmiParameters must name only the public Amazon Linux AMI parameters"
  }
}

run "wildcards_are_known_gaps" {
  command = plan

  assert {
    condition     = sort([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Sid if s.Resource == "*"]) == tolist(["DescribeEc2", "DescribeLogGroups", "DescribeParameters"])
    error_message = "only the documented describe actions may use Resource = *"
  }
}

run "no_writes" {
  command = plan

  assert {
    condition = alltrue([
      for a in flatten([for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Action]))]) :
      can(regex("^(ec2:Describe|ec2:Get|iam:Get|iam:List|ecr:Describe|ecr:List|ecr:GetRepositoryPolicy|ecr:GetLifecyclePolicy|ssm:GetParameter|ssm:DescribeParameters|ssm:ListTagsForResource|logs:Describe|logs:ListTagsForResource|s3:GetBucket|s3:GetEncryptionConfiguration|s3:GetLifecycleConfiguration|s3:GetAccelerateConfiguration|s3:GetReplicationConfiguration|s3:ListBucket$|logs:FilterLogEvents|logs:GetLogEvents)", a))
    ])
    error_message = "container/read must grant read-only actions: ${join(", ", [for a in flatten([for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Action]))]) : a if !can(regex("^(ec2:Describe|ec2:Get|iam:Get|iam:List|ecr:Describe|ecr:List|ecr:GetRepositoryPolicy|ecr:GetLifecyclePolicy|ssm:GetParameter|ssm:DescribeParameters|ssm:ListTagsForResource|logs:Describe|logs:ListTagsForResource|s3:GetBucket|s3:GetEncryptionConfiguration|s3:GetLifecycleConfiguration|s3:GetAccelerateConfiguration|s3:GetReplicationConfiguration|s3:ListBucket$|logs:FilterLogEvents|logs:GetLogEvents)", a))])}"
  }
}

run "no_object_reads" {
  command = plan

  assert {
    condition     = !anytrue([for a in flatten([for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Action]))]) : can(regex("^s3:GetObject", a))])
    error_message = "the records themselves are never readable by CI"
  }
}

# `description` forces replacement of the policy, which would detach it from
# every role mid-apply. It is frozen; change the README instead.
run "description_is_frozen" {
  command = plan

  assert {
    condition     = aws_iam_policy.this.description == "CI policy container/read: read the project's network, instance, instance role, image repository, parameters, log group and records bucket"
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

# aws_s3_bucket refresh reads the replication configuration and fails on
# AccessDenied; s3:GetReplicationConfiguration is not matched by s3:GetBucket*.
run "records_bucket_refresh" {
  command = plan

  assert {
    condition = contains(
      flatten([[for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ReadRecordsBucket"][0].Action]),
      "s3:GetReplicationConfiguration"
    )
    error_message = "the plan and apply roles must be able to refresh the records bucket"
  }
}

# `bot logs` runs with the plan role.
run "reads_the_bot_logs" {
  command = plan

  assert {
    condition = alltrue([
      for a in ["logs:FilterLogEvents", "logs:GetLogEvents", "logs:DescribeLogStreams"] :
      contains(flatten([[for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ReadProjectLogGroups"][0].Action]), a)
    ])
    error_message = "the plan role must be able to read the bot's log events"
  }

  assert {
    condition = alltrue([
      for r in flatten([[for s in jsondecode(aws_iam_policy.this.policy).Statement : s if s.Sid == "ReadProjectLogGroups"][0].Resource]) :
      startswith(r, "arn:aws:logs:us-east-1:123456789012:log-group:/jwall-engineering/rusty-chess/")
    ])
    error_message = "log reads stay limited to the project's log groups"
  }
}
