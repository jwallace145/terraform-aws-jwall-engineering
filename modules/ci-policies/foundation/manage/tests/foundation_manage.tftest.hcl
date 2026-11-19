mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  name             = "jwall-engineering-infra-ci-apply-foundation-manage"
  state_bucket_arn = "arn:aws:s3:::jwall-engineering-tfstate"
  hosted_zone_arn  = "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ"
}

# The default pattern jwall-engineering-* matches the state bucket. Granting
# s3:* on <pattern>/* would expose every project's state, so the policy only
# ever names bucket ARNs.
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
    condition     = [for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "ManageSiteBuckets"][0] == ["arn:aws:s3:::jwall-engineering-*"]
    error_message = "ManageSiteBuckets must cover only the managed bucket ARNs"
  }
}

run "denies_state_bucket_deletion" {
  command = plan

  assert {
    condition = contains(jsondecode(aws_iam_policy.this.policy).Statement, {
      Sid      = "DenyStateBucketDeletion"
      Effect   = "Deny"
      Action   = ["s3:DeleteBucket", "s3:DeleteBucketPolicy"]
      Resource = "arn:aws:s3:::jwall-engineering-tfstate"
    })
    error_message = "the state bucket and its policy must not be deletable"
  }
}

run "attach_is_allow_listed" {
  command = plan

  assert {
    condition     = [for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Condition.ArnLike["iam:PolicyARN"] if s.Sid == "AttachAllowListedPolicies"][0] == ["arn:aws:iam::123456789012:policy/jwall-engineering-*"]
    error_message = "by default only <name_root>-* customer-managed policies may be attached; ReadOnlyAccess is no longer in the list"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_policy.this.policy).Statement :
      s.Resource == "arn:aws:iam::123456789012:role/jwall-engineering-*" || s.Resource == "arn:aws:iam::123456789012:policy/jwall-engineering-*"
      if startswith(flatten([s.Action])[0], "iam:")
    ])
    error_message = "IAM actions must be limited to <name_root>-* roles and policies"
  }
}

run "rejects_wildcard_attachable_policy" {
  command = plan

  variables {
    attachable_policy_arns = ["arn:aws:iam::aws:policy/*"]
  }

  expect_failures = [var.attachable_policy_arns]
}

run "ecr_manages_repositories_not_images" {
  command = plan

  assert {
    condition     = [for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "ManageOrganisationRepositories"][0] == "arn:aws:ecr:us-east-1:123456789012:repository/jwall-engineering-*"
    error_message = "ECR management must be limited to <name_root>-* repositories"
  }

  assert {
    condition = alltrue([
      for a in [for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Action if s.Sid == "ManageOrganisationRepositories"][0] :
      !contains(["ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:BatchDeleteImage"], a)
    ])
    error_message = "foundation/manage must not push or delete images; that is ecr/push"
  }
}

# `description` forces replacement of the policy, which would detach it from
# every role mid-apply. It is frozen; change the README instead.
run "description_is_frozen" {
  command = plan

  assert {
    condition     = aws_iam_policy.this.description == "CI policy foundation/manage: manage the state bucket configuration, managed buckets, <name_root>-* IAM and the hosted zone"
    error_message = "the policy description must never change: it forces replacement"
  }
}

run "no_service_linked_role_statements_by_default" {
  command = plan

  assert {
    condition     = length([for s in jsondecode(aws_iam_policy.this.policy).Statement : s if strcontains(s.Sid, "ServiceLinkedRole")]) == 0
    error_message = "without service_linked_role_services the policy must not mention service-linked roles"
  }
}

run "service_linked_roles_are_created_only_for_the_named_services" {
  command = plan

  variables {
    service_linked_role_services = ["spot.amazonaws.com"]
  }

  assert {
    condition = contains(jsondecode(aws_iam_policy.this.policy).Statement, {
      Sid       = "CreateServiceLinkedRoles"
      Effect    = "Allow"
      Action    = "iam:CreateServiceLinkedRole"
      Resource  = ["arn:aws:iam::123456789012:role/aws-service-role/spot.amazonaws.com/*"]
      Condition = { StringEquals = { "iam:AWSServiceName" = ["spot.amazonaws.com"] } }
    })
    error_message = "CreateServiceLinkedRole must be limited to the named services, by resource and by iam:AWSServiceName"
  }

  assert {
    condition     = [for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "ManageServiceLinkedRoles"][0] == ["arn:aws:iam::123456789012:role/aws-service-role/spot.amazonaws.com/*"]
    error_message = "ManageServiceLinkedRoles must cover only the named services' roles"
  }

  # The module never deletes a service-linked role, so nothing grants it.
  assert {
    condition = !anytrue(flatten([
      for s in jsondecode(aws_iam_policy.this.policy).Statement : [
        for a in flatten([s.Action]) : s.Effect == "Allow" && contains(["iam:DeleteServiceLinkedRole", "iam:DeleteRole", "iam:*"], a) && anytrue([for r in flatten([s.Resource]) : strcontains(r, "aws-service-role")])
      ]
    ]))
    error_message = "no statement may allow deleting a service-linked role"
  }
}

run "rejects_a_non_service_principal" {
  command = plan

  variables {
    service_linked_role_services = ["spot"]
  }

  expect_failures = [var.service_linked_role_services]
}
