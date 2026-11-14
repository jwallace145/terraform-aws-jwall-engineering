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
  name                 = "jwall-engineering-databricks-poc-ci-apply-databricks-manage"
  project              = "databricks-poc"
  secret_parameter_arn = "arn:aws:ssm:us-east-1:123456789012:parameter/jwall-engineering/databricks-poc/databricks"
  events_object_arn    = "arn:aws:s3:::jwall-engineering-databricks-audit-logs/events/project=databricks-poc/*"
}

run "has_exactly_the_databricks_manage_statements" {
  command = plan

  assert {
    condition = jsonencode(sort([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Sid])) == jsonencode(sort([
      "ManageDatabricksBuckets",
      "ListDatabricksBuckets",
      "EmptyDatabricksBuckets",
      "CreateS3Endpoint",
      "CreateNatNetworkResources",
      "ManageInProjectNetwork",
      "RunNatInstance",
      "RunNatVolume",
      "RunFromAmazonImages",
      "RunNatInProjectNetwork",
      "TerminateNatInstance",
      "TagOnCreate",
      "TagNatRootVolume",
      "ReadSecret",
      "DecryptSecretThroughSsm",
      "AppendEvents",
    ]))
    error_message = "databricks/manage holds the bucket, NAT, endpoint, secret and event log statements only"
  }

  assert {
    condition     = alltrue([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Effect == "Allow"])
    error_message = "every statement is an Allow"
  }
}

run "buckets_are_configured_by_name" {
  command = plan

  assert {
    condition = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "ManageDatabricksBuckets"])) == jsonencode([
      "arn:aws:s3:::jwall-engineering-databricks-poc-databricks-root",
      "arn:aws:s3:::jwall-engineering-databricks-poc-databricks-catalog",
    ])
    error_message = "bucket configuration on the root and catalog buckets only"
  }

  # Everything databricks-workspace and databricks-catalog configure.
  assert {
    condition = jsonencode(sort(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Action if s.Sid == "ManageDatabricksBuckets"]))) == jsonencode(sort([
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutEncryptionConfiguration",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketOwnershipControls",
      "s3:PutBucketTagging",
    ]))
    error_message = "the bucket configuration the two modules manage, nothing on objects"
  }
}

run "databricks_manage_no_object_read" {
  command = plan

  # No statement grants an object read or write on either bucket.
  assert {
    condition = !anytrue(flatten([
      for s in jsondecode(aws_iam_policy.this.policy).Statement : [
        for a in tolist(flatten([s.Action])) : can(regex("^s3:(\\*|Get|Put)Object", a))
      ]
      if anytrue([for r in tolist(flatten([s.Resource])) : can(regex("^arn:aws:s3:::jwall-engineering-databricks-poc-databricks-(root|catalog)", r))])
    ]))
    error_message = "never s3:GetObject* or s3:PutObject* on the root or catalog bucket"
  }

  # The one object write in the policy is the event log append.
  assert {
    condition = jsonencode([
      for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Sid
      if anytrue([for a in tolist(flatten([s.Action])) : can(regex("^s3:(\\*|Get|Put)Object", a))])
    ]) == jsonencode(["AppendEvents"])
    error_message = "only AppendEvents may write an object"
  }
}

# Ruling R7: the CLI empties the catalog bucket through its bucket policy, but
# the force_destroy backstop runs after the policy is gone and needs these.
run "buckets_can_be_emptied_for_force_destroy" {
  command = plan

  assert {
    condition = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : { a = sort(s.Action), r = s.Resource } if s.Sid == "ListDatabricksBuckets"])) == jsonencode({
      a = ["s3:ListBucket", "s3:ListBucketVersions"]
      r = [
        "arn:aws:s3:::jwall-engineering-databricks-poc-databricks-root",
        "arn:aws:s3:::jwall-engineering-databricks-poc-databricks-catalog",
      ]
    })
    error_message = "list the current objects and their versions of both buckets"
  }

  assert {
    condition = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : { a = sort(s.Action), r = s.Resource } if s.Sid == "EmptyDatabricksBuckets"])) == jsonencode({
      a = ["s3:DeleteObject", "s3:DeleteObjectVersion"]
      r = [
        "arn:aws:s3:::jwall-engineering-databricks-poc-databricks-root/*",
        "arn:aws:s3:::jwall-engineering-databricks-poc-databricks-catalog/*",
      ]
    })
    error_message = "delete objects and object versions of both buckets, nothing else"
  }
}

run "nat_launch_requires_component_tag" {
  command = plan

  assert {
    condition = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : { a = s.Action, r = s.Resource, c = s.Condition } if s.Sid == "RunNatInstance"])) == jsonencode({
      a = "ec2:RunInstances"
      r = "arn:aws:ec2:us-east-1:123456789012:instance/*"
      c = {
        StringEquals = {
          "aws:RequestTag/Component" = "nat-instance"
          "aws:RequestTag/Project"   = "databricks-poc"
        }
        StringLike = { "ec2:InstanceType" = "t4g.*" }
      }
    })
    error_message = "a NAT launch needs Project and Component = nat-instance (StringEquals) and a t4g type (StringLike)"
  }

  assert {
    condition = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : { r = s.Resource, c = s.Condition } if s.Sid == "TerminateNatInstance"])) == jsonencode({
      r = "arn:aws:ec2:us-east-1:123456789012:instance/*"
      c = {
        StringEquals = {
          "aws:ResourceTag/Component" = "nat-instance"
          "aws:ResourceTag/Project"   = "databricks-poc"
        }
      }
    })
    error_message = "only the project's NAT instance may be terminated"
  }
}

# A `*` under StringEquals is a literal asterisk, not a wildcard.
run "no_wildcard_under_string_equals" {
  command = plan

  assert {
    condition = !anytrue(flatten([
      for s in jsondecode(aws_iam_policy.this.policy).Statement : [
        for k, v in try(s.Condition.StringEquals, {}) : [for x in tolist(flatten([v])) : strcontains(x, "*")]
      ]
    ]))
    error_message = "StringEquals values must not contain *; use StringLike"
  }
}

# The other resources RunInstances authorizes. None of them is created with
# request tags, so none may be conditioned on aws:RequestTag.
run "run_instances_touches_only_scoped_resources" {
  command = plan

  assert {
    condition = jsonencode(sort(flatten([
      for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Resource]))
      if contains(tolist(flatten([s.Action])), "ec2:RunInstances")
      ]))) == jsonencode(sort([
      "arn:aws:ec2:us-east-1:123456789012:instance/*",
      "arn:aws:ec2:us-east-1:123456789012:volume/*",
      "arn:aws:ec2:us-east-1::image/*",
      "arn:aws:ec2:us-east-1:123456789012:subnet/*",
      "arn:aws:ec2:us-east-1:123456789012:security-group/*",
      "arn:aws:ec2:us-east-1:123456789012:network-interface/*",
    ]))
    error_message = "RunInstances reaches the instance, its root volume, an image and the project network"
  }

  assert {
    condition     = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Condition if s.Sid == "RunFromAmazonImages"])) == jsonencode({ StringEquals = { "ec2:Owner" = "amazon" } })
    error_message = "images by owner, not by tag: AMIs carry no project tag"
  }

  assert {
    condition     = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Condition if s.Sid == "RunNatInProjectNetwork"])) == jsonencode({ StringEquals = { "aws:ResourceTag/Project" = "databricks-poc" } })
    error_message = "the existing subnet, security group and ENI must be the project's"
  }

  # The provider tags the root volume after launch, so the launch request may
  # carry no volume tags: a tag condition here would deny every launch.
  assert {
    condition     = one([for s in jsondecode(aws_iam_policy.this.policy).Statement : try(s.Condition, null) if s.Sid == "RunNatVolume"]) == null
    error_message = "the root volume is bounded by the instance it is launched with, not by request tags"
  }
}

# aws:RequestTag only exists on a request that creates a tagged resource.
run "request_tags_only_on_resources_created_with_tags" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for s in jsondecode(aws_iam_policy.this.policy).Statement : [
        for r in tolist(flatten([s.Resource])) : can(regex(":(instance|vpc-endpoint|network-interface|elastic-ip|volume)/\\*$", r))
      ]
      if length([for k in keys(merge(values(try(s.Condition, {}))...)) : k if startswith(k, "aws:RequestTag/")]) > 0
    ]))
    error_message = "aws:RequestTag conditions only on resources a request creates with tags"
  }
}

run "nat_network_resources_by_tag" {
  command = plan

  assert {
    condition = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : { a = sort(s.Action), r = s.Resource, c = s.Condition } if s.Sid == "CreateNatNetworkResources"])) == jsonencode({
      a = ["ec2:AllocateAddress", "ec2:CreateNetworkInterface"]
      r = [
        "arn:aws:ec2:us-east-1:123456789012:network-interface/*",
        "arn:aws:ec2:us-east-1:123456789012:elastic-ip/*",
      ]
      c = { StringEquals = { "aws:RequestTag/Project" = "databricks-poc" } }
    })
    error_message = "the ENI and the Elastic IP are created with the Project tag"
  }

  assert {
    condition = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : { r = s.Resource, c = s.Condition } if s.Sid == "CreateS3Endpoint"])) == jsonencode({
      r = "arn:aws:ec2:us-east-1:123456789012:vpc-endpoint/*"
      c = {
        StringEquals = {
          "aws:RequestTag/Project" = "databricks-poc"
          "ec2:VpceServiceName"    = "com.amazonaws.us-east-1.s3"
        }
      }
    })
    error_message = "only the S3 gateway endpoint, created with the Project tag"
  }

  assert {
    condition     = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Condition if s.Sid == "ManageInProjectNetwork"])) == jsonencode({ StringEquals = { "aws:ResourceTag/Project" = "databricks-poc" } })
    error_message = "every change to existing network resources needs the Project tag"
  }

  # Ruling R1 (EIP lifecycle), the ENI's source/dest check, the endpoint, and
  # routes whose target is the NAT's ENI.
  assert {
    condition = alltrue([
      for a in [
        "ec2:AssociateAddress", "ec2:DisassociateAddress", "ec2:ReleaseAddress",
        "ec2:ModifyNetworkInterfaceAttribute", "ec2:DeleteNetworkInterface", "ec2:CreateNetworkInterface",
        "ec2:CreateVpcEndpoint", "ec2:ModifyVpcEndpoint", "ec2:DeleteVpcEndpoints",
        "ec2:CreateRoute", "ec2:ReplaceRoute",
      ] :
      contains(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Action if s.Sid == "ManageInProjectNetwork"]), a)
    ])
    error_message = "the EIP, ENI, endpoint and route actions on existing project resources"
  }

  assert {
    condition = jsonencode(sort(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "ManageInProjectNetwork"]))) == jsonencode(sort([
      "arn:aws:ec2:us-east-1:123456789012:vpc/*",
      "arn:aws:ec2:us-east-1:123456789012:subnet/*",
      "arn:aws:ec2:us-east-1:123456789012:route-table/*",
      "arn:aws:ec2:us-east-1:123456789012:security-group/*",
      "arn:aws:ec2:us-east-1:123456789012:vpc-endpoint/*",
      "arn:aws:ec2:us-east-1:123456789012:network-interface/*",
      "arn:aws:ec2:us-east-1:123456789012:elastic-ip/*",
    ]))
    error_message = "existing project network resources by type"
  }
}

run "tags_on_create_are_bounded_to_this_policys_create_calls" {
  command = plan

  assert {
    condition = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : sort(s.Condition.StringEquals["ec2:CreateAction"]) if s.Sid == "TagOnCreate"])) == jsonencode(sort([
      "AllocateAddress",
      "CreateNetworkInterface",
      "CreateVpcEndpoint",
      "RunInstances",
    ]))
    error_message = "TagOnCreate must be bounded to the create calls this policy allows"
  }

  assert {
    condition     = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : { r = s.Resource, c = s.Condition } if s.Sid == "TagNatRootVolume"])) == jsonencode({ r = "arn:aws:ec2:us-east-1:123456789012:volume/*", c = { StringEquals = { "aws:RequestTag/Component" = "nat-instance" } } })
    error_message = "the post-launch root volume tagging carries Component = nat-instance"
  }
}

# compute/manage, which the apply role also holds, already manages the VPC,
# subnets, route tables, security groups and every <name_root>-<project>-*
# role, which covers the -databricks- roles. Neither the cross-account nor the
# Unity Catalog role is passed to an AWS service, so there is no PassRole.
run "no_iam" {
  command = plan

  assert {
    condition     = !anytrue([for a in flatten([for s in jsondecode(aws_iam_policy.this.policy).Statement : tolist(flatten([s.Action]))]) : startswith(a, "iam:")])
    error_message = "IAM comes from compute/manage; no iam:PassRole is needed"
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
    condition = jsonencode(one([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Condition if s.Sid == "DecryptSecretThroughSsm"])) == jsonencode({
      StringEquals = {
        "kms:EncryptionContext:PARAMETER_ARN" = "arn:aws:ssm:us-east-1:123456789012:parameter/jwall-engineering/databricks-poc/databricks"
        "kms:ViaService"                      = "ssm.us-east-1.amazonaws.com"
      }
    })
    error_message = "kms:Decrypt only through SSM, and only for the one parameter"
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
}

run "wildcards_are_known_gaps" {
  command = plan

  assert {
    condition     = length([for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Sid if s.Resource == "*"]) == 0
    error_message = "no Resource = *"
  }
}

# `description` forces replacement of the policy; it is frozen.
run "description_is_frozen" {
  command = plan

  assert {
    condition     = aws_iam_policy.this.description == "CI policy databricks/manage: create and manage the project's Databricks workspace infrastructure"
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
