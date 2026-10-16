mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  name              = "jwall-engineering-infra-ci-plan-foundation-read"
  state_bucket_arn  = "arn:aws:s3:::jwall-engineering-tfstate"
  hosted_zone_arn   = "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
}

run "read_only" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for s in jsondecode(aws_iam_policy.this.policy).Statement : [
        for a in flatten([s.Action]) : can(regex("^[a-z0-9]+:(Get|List|Describe)", a))
      ]
    ]))
    error_message = "foundation/read must grant only Get*, List* and Describe* actions"
  }
}

# ReadOnlyAccess grants s3:GetObject on every bucket, which exposes every
# project's state. This policy must never reach an object.
run "never_reaches_objects" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for s in jsondecode(aws_iam_policy.this.policy).Statement : [
        for r in flatten([s.Resource]) : !(startswith(r, "arn:aws:s3:::") && strcontains(r, "/"))
      ]
    ]))
    error_message = "no S3 resource may be an object ARN"
  }

  assert {
    condition = [for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "ReadManagedBuckets"][0] == [
      "arn:aws:s3:::jwall-engineering-tfstate",
      "arn:aws:s3:::jwall-engineering-*",
    ]
    error_message = "bucket reads must cover the state bucket and the managed bucket patterns"
  }
}

run "iam_is_limited_to_the_namespace" {
  command = plan

  assert {
    condition = (
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "ReadOrganisationRoles"][0] == "arn:aws:iam::123456789012:role/jwall-engineering-*" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "ReadOrganisationPolicies"][0] == "arn:aws:iam::123456789012:policy/jwall-engineering-*" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "ReadGitHubOidcProvider"][0] == var.oidc_provider_arn
    )
    error_message = "IAM reads must be limited to <name_root>-* and the GitHub OIDC provider"
  }
}

run "ecr_is_limited_to_the_namespace" {
  command = plan

  assert {
    condition     = [for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "ReadOrganisationRepositories"][0] == "arn:aws:ecr:us-east-1:123456789012:repository/jwall-engineering-*"
    error_message = "ECR reads must be limited to <name_root>-* repositories"
  }
}

# `description` forces replacement of the policy, which would detach it from
# every role mid-apply. It is frozen; change the README instead.
run "description_is_frozen" {
  command = plan

  assert {
    condition     = aws_iam_policy.this.description == "CI policy foundation/read: read the state bucket, managed buckets, <name_root>-* IAM, the GitHub OIDC provider and the hosted zone"
    error_message = "the policy description must never change: it forces replacement"
  }
}
