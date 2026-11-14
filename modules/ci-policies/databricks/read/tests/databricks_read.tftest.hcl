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
  name                 = "jwall-engineering-databricks-poc-ci-plan-databricks-read"
  project              = "databricks-poc"
  secret_parameter_arn = "arn:aws:ssm:us-east-1:123456789012:parameter/jwall-engineering/databricks-poc/databricks"
  events_object_arn    = "arn:aws:s3:::jwall-engineering-databricks-audit-logs/events/project=databricks-poc/*"
}

run "has_exactly_the_databricks_read_statements" {
  command = plan

  assert {
    condition = jsonencode(sort([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Sid])) == jsonencode([
      "AppendEvents",
      "DecryptSecretThroughSsm",
      "ReadDatabricksBuckets",
      "ReadSecret",
    ])
    error_message = "databricks/read holds the bucket reads, the secret read and the event log append only"
  }

  assert {
    condition     = alltrue([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Effect == "Allow"])
    error_message = "every statement is an Allow"
  }
}

# The plan role trusts pull_request. Apart from the append-only event log, the
# policy may only read; the event log is the single exception and is checked
# by events_put_only_under_project_prefix.
run "databricks_read_is_read_only" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for s in jsondecode(aws_iam_policy.this.policy).Statement : [
        for a in tolist(flatten([s.Action])) :
        can(regex("^[a-z0-9]+:(Get|List|Describe)", a)) || contains(["ssm:GetParameter", "kms:Decrypt"], a)
      ] if s.Sid != "AppendEvents"
    ]))
    error_message = "databricks/read may only Get, List or Describe, read the one parameter and decrypt it"
  }

  assert {
    condition     = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Action if s.Sid == "AppendEvents"])) == jsonencode("s3:PutObject")
    error_message = "the only write is s3:PutObject in AppendEvents"
  }
}

run "buckets_are_configuration_reads_on_the_two_buckets" {
  command = plan

  assert {
    condition = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "ReadDatabricksBuckets"])) == jsonencode([
      "arn:aws:s3:::jwall-engineering-databricks-poc-databricks-root",
      "arn:aws:s3:::jwall-engineering-databricks-poc-databricks-catalog",
    ])
    error_message = "bucket reads name the root and catalog bucket ARNs, never their objects"
  }

  # Refresh of aws_s3_bucket: HeadBucket needs s3:ListBucket, the rest are
  # configuration reads.
  assert {
    condition = alltrue([
      for a in ["s3:GetBucket*", "s3:GetEncryptionConfiguration", "s3:GetLifecycleConfiguration", "s3:GetAccelerateConfiguration", "s3:GetReplicationConfiguration", "s3:ListBucket"] :
      contains(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Action if s.Sid == "ReadDatabricksBuckets"]), a)
    ])
    error_message = "everything a refresh of the buckets reads"
  }

  assert {
    condition     = !anytrue([for a in flatten([for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Action]))]) : can(regex("^s3:GetObject", a))])
    error_message = "never an object read"
  }
}

run "secret_scoped_to_one_parameter" {
  command = plan

  assert {
    condition = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : { a = s.Action, r = s.Resource } if s.Sid == "ReadSecret"])) == jsonencode({
      a = "ssm:GetParameter"
      r = "arn:aws:ssm:us-east-1:123456789012:parameter/jwall-engineering/databricks-poc/databricks"
    })
    error_message = "ssm:GetParameter on the one secret parameter"
  }

  assert {
    condition = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : { a = s.Action, r = s.Resource, c = s.Condition } if s.Sid == "DecryptSecretThroughSsm"])) == jsonencode({
      a = "kms:Decrypt"
      r = "arn:aws:kms:us-east-1:123456789012:key/*"
      c = {
        StringEquals = {
          "kms:EncryptionContext:PARAMETER_ARN" = "arn:aws:ssm:us-east-1:123456789012:parameter/jwall-engineering/databricks-poc/databricks"
          "kms:ViaService"                      = "ssm.us-east-1.amazonaws.com"
        }
      }
    })
    error_message = "kms:Decrypt only through SSM, and only for the one parameter's encryption context"
  }
}

run "events_put_only_under_project_prefix" {
  command = plan

  assert {
    condition = jsonencode([
      for s in jsondecode(aws_iam_policy.this.policy).Statement : { a = s.Action, r = s.Resource }
      if anytrue([for r in tolist(flatten([s.Resource])) : startswith(r, "arn:aws:s3:::jwall-engineering-databricks-audit-logs")])
      ]) == jsonencode([{
        a = "s3:PutObject"
        r = "arn:aws:s3:::jwall-engineering-databricks-audit-logs/events/project=databricks-poc/*"
    }])
    error_message = "the only action on the audit bucket is s3:PutObject under events/project=<project>/"
  }

  assert {
    condition     = endswith(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "AppendEvents"]), "/events/project=databricks-poc/*")
    error_message = "the event log resource ends in /events/project=<project>/*"
  }
}

# compute/read, which the plan and apply roles also hold, already describes EC2
# and reads <name_root>-<project>-* roles; nothing here repeats it.
run "does_not_repeat_compute_read" {
  command = plan

  assert {
    condition     = !anytrue([for a in flatten([for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Action]))]) : can(regex("^(ec2|iam):", a))])
    error_message = "EC2 describes and IAM reads come from compute/read"
  }
}

run "wildcards_are_known_gaps" {
  command = plan

  assert {
    condition     = length([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Sid if s.Resource == "*"]) == 0
    error_message = "no Resource = *"
  }
}

run "rejects_a_wildcard_secret" {
  command = plan

  variables {
    secret_parameter_arn = "arn:aws:ssm:us-east-1:123456789012:parameter/jwall-engineering/*"
  }

  expect_failures = [var.secret_parameter_arn]
}

run "rejects_another_projects_events" {
  command = plan

  variables {
    events_object_arn = "arn:aws:s3:::jwall-engineering-databricks-audit-logs/events/project=other/*"
  }

  expect_failures = [var.events_object_arn]
}

run "rejects_the_whole_audit_bucket" {
  command = plan

  variables {
    events_object_arn = "arn:aws:s3:::jwall-engineering-databricks-audit-logs/*"
  }

  expect_failures = [var.events_object_arn]
}

# `description` forces replacement of the policy; it is frozen.
run "description_is_frozen" {
  command = plan

  assert {
    condition     = aws_iam_policy.this.description == "CI policy databricks/read: read the project's Databricks workspace infrastructure and the Databricks credential"
    error_message = "the policy description must never change: it forces replacement"
  }
}

run "fits_policy_size_limit" {
  command = plan

  assert {
    condition     = length(aws_iam_policy.this.policy) < 6144
    error_message = "managed policies are limited to 6144 characters"
  }
}
