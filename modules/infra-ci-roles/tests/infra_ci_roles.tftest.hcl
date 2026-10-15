mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  repository        = "jwallace145/jwall-engineering-infra"
  owner_id          = "35950238"
  repository_id     = "1420037633"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  state_bucket_arn  = "arn:aws:s3:::jwall-engineering-tfstate"
  state_key         = "project=infra/env=prod/infra-prod.tfstate"
  hosted_zone_arn   = "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ"
}

run "role_names_descriptions_and_tags" {
  command = plan

  assert {
    condition = (
      module.plan.name == "jwall-engineering-infra-ci-plan" &&
      module.apply.name == "jwall-engineering-infra-ci-apply"
    )
    error_message = "roles must be named <name_root>-<project>-ci-{plan,apply}"
  }

  assert {
    condition = (
      local.descriptions.plan == "terraform plan for jwallace145/jwall-engineering-infra pull requests (read-only)" &&
      local.descriptions.apply == "terraform apply for jwallace145/jwall-engineering-infra releases (prod environment)"
    )
    error_message = "descriptions must match the roles the infra repo already has"
  }

  assert {
    condition = (
      module.plan.tags == tomap({ Name = "jwall-engineering-infra-ci-plan", Component = "ci" }) &&
      module.apply.tags == tomap({ Name = "jwall-engineering-infra-ci-apply", Component = "ci" })
    )
    error_message = "each role must be tagged Name = <role name> and Component = ci"
  }

  assert {
    condition = (
      output.plan_role_name == "jwall-engineering-infra-ci-plan" &&
      output.apply_role_name == "jwall-engineering-infra-ci-apply"
    )
    error_message = "name outputs must describe the two roles"
  }
}

# ARNs are only known after apply (the mock provider generates them).
run "arn_outputs" {
  command = apply

  assert {
    condition = (
      output.plan_role_arn == module.plan.arn &&
      output.apply_role_arn == module.apply.arn &&
      output.plan_role_arn != output.apply_role_arn
    )
    error_message = "ARN outputs must be the two roles' ARNs"
  }
}

run "role_names_follow_name_root_and_project" {
  command = plan

  variables {
    name_root = "prog-strength"
    project   = "foundation"
  }

  assert {
    condition = (
      module.plan.name == "prog-strength-foundation-ci-plan" &&
      module.apply.name == "prog-strength-foundation-ci-apply"
    )
    error_message = "role names must be built from name_root and project"
  }
}

run "trust_subjects" {
  command = plan

  assert {
    condition = jsondecode(module.plan.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == [
      "repo:jwallace145/jwall-engineering-infra:pull_request",
      "repo:jwallace145@35950238/jwall-engineering-infra@1420037633:pull_request",
    ]
    error_message = "plan role must trust pull_request in both subject forms"
  }

  assert {
    condition = jsondecode(module.apply.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == [
      "repo:jwallace145/jwall-engineering-infra:environment:prod",
      "repo:jwallace145@35950238/jwall-engineering-infra@1420037633:environment:prod",
    ]
    error_message = "apply role must trust environment:prod in both subject forms"
  }

  assert {
    condition = (
      alltrue([for s in jsondecode(module.plan.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] : endswith(s, ":pull_request")]) &&
      alltrue([for s in jsondecode(module.apply.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] : endswith(s, ":environment:prod")])
    )
    error_message = "plan subjects end in :pull_request and apply subjects in :environment:prod"
  }

  assert {
    condition = (
      jsondecode(module.plan.assume_role_policy).Statement[0].Sid == "GitHubPullRequests" &&
      jsondecode(module.apply.assume_role_policy).Statement[0].Sid == "GitHubProdEnvironment"
    )
    error_message = "trust statement Sids must match the roles the infra repo already has"
  }
}

run "apply_environment_sets_subject_description_and_sid" {
  command = plan

  variables {
    apply_environment = "staging-eu"
  }

  assert {
    condition     = alltrue([for s in jsondecode(module.apply.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] : endswith(s, ":environment:staging-eu")])
    error_message = "apply subjects must use apply_environment"
  }

  assert {
    condition     = local.descriptions.apply == "terraform apply for jwallace145/jwall-engineering-infra releases (staging-eu environment)"
    error_message = "apply description must name apply_environment"
  }

  assert {
    condition     = jsondecode(module.apply.assume_role_policy).Statement[0].Sid == "GitHubStagingEuEnvironment"
    error_message = "apply trust Sid must be GitHub<Environment>Environment"
  }
}

run "managed_and_inline_policy_layout" {
  command = plan

  assert {
    condition = (
      module.plan.managed_policy_arns == tolist(["arn:aws:iam::aws:policy/ReadOnlyAccess"]) &&
      module.apply.managed_policy_arns == tolist(["arn:aws:iam::aws:policy/ReadOnlyAccess"])
    )
    error_message = "both roles attach exactly ReadOnlyAccess"
  }

  assert {
    condition = (
      keys(module.plan.inline_policies) == ["state"] &&
      module.plan.inline_policies["state"].name == "jwall-engineering-infra-ci-plan-state" &&
      keys(module.apply.inline_policies) == ["manage"] &&
      module.apply.inline_policies["manage"].name == "jwall-engineering-infra-ci-apply-manage"
    )
    error_message = "inline policies must be <plan role>-state and <apply role>-manage"
  }
}

run "plan_role_state_policy" {
  command = plan

  assert {
    condition     = [for s in jsondecode(module.plan.inline_policies["state"].policy).Statement : s.Sid] == ["ListOwnStatePrefix", "ReadOwnState", "LockOwnState"]
    error_message = "plan policy must have exactly ListOwnStatePrefix, ReadOwnState, LockOwnState"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(module.plan.inline_policies["state"].policy).Statement :
      s.Sid == "ListOwnStatePrefix" && s.Action == "s3:ListBucket" && s.Resource == "arn:aws:s3:::jwall-engineering-tfstate"
      && s.Condition.StringLike["s3:prefix"] == "project=infra/env=prod/infra-prod.tfstate*"
    ])
    error_message = "plan role lists only its own state prefix"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(module.plan.inline_policies["state"].policy).Statement :
      s.Sid == "ReadOwnState" && s.Action == ["s3:GetObject", "s3:GetObjectVersion"] && s.Resource == [
        "arn:aws:s3:::jwall-engineering-tfstate/project=infra/env=prod/infra-prod.tfstate",
        "arn:aws:s3:::jwall-engineering-tfstate/project=infra/env=prod/infra-prod.tfstate.tflock",
      ]
    ])
    error_message = "plan role reads only its own state object and lock"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(module.plan.inline_policies["state"].policy).Statement :
      s.Sid == "LockOwnState" && s.Action == ["s3:PutObject", "s3:DeleteObject"]
      && s.Resource == "arn:aws:s3:::jwall-engineering-tfstate/project=infra/env=prod/infra-prod.tfstate.tflock"
    ])
    error_message = "plan role writes only its own lock file"
  }
}

run "apply_role_manage_policy" {
  command = plan

  assert {
    condition = [for s in jsondecode(module.apply.inline_policies["manage"].policy).Statement : s.Sid] == [
      "ListOwnStatePrefix",
      "ReadWriteOwnState",
      "LockOwnState",
      "ManageStateBucketConfiguration",
      "ManageSiteBuckets",
      "DenyStateBucketDeletion",
      "ManageOrganisationRoles",
      "AttachAllowListedPolicies",
      "ManageOrganisationPolicies",
      "ManageHostedZone",
      "ReadRoute53Changes",
    ]
    error_message = "apply policy must have exactly the eleven statements of the infra repo, in order"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(module.apply.inline_policies["manage"].policy).Statement :
      s.Sid == "AttachAllowListedPolicies" && s.Effect == "Allow" && s.Action == "iam:AttachRolePolicy"
      && s.Resource == "arn:aws:iam::123456789012:role/jwall-engineering-*"
      && s.Condition.ArnLike["iam:PolicyARN"] == [
        "arn:aws:iam::aws:policy/ReadOnlyAccess",
        "arn:aws:iam::123456789012:policy/jwall-engineering-*",
      ]
    ])
    error_message = "AttachAllowListedPolicies must carry an ArnLike iam:PolicyARN allow-list"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(module.apply.inline_policies["manage"].policy).Statement :
      s.Sid == "DenyStateBucketDeletion" && s.Effect == "Deny"
      && contains(s.Action, "s3:DeleteBucket") && contains(s.Action, "s3:DeleteBucketPolicy")
      && s.Resource == "arn:aws:s3:::jwall-engineering-tfstate"
    ])
    error_message = "DenyStateBucketDeletion must deny s3:DeleteBucket on the state bucket"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(module.apply.inline_policies["manage"].policy).Statement :
      s.Sid == "ManageOrganisationRoles" && s.Resource == "arn:aws:iam::123456789012:role/jwall-engineering-*"
    ])
    error_message = "ManageOrganisationRoles must be limited to <name_root>-* roles"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(module.apply.inline_policies["manage"].policy).Statement :
      s.Sid == "ManageOrganisationPolicies" && s.Resource == "arn:aws:iam::123456789012:policy/jwall-engineering-*"
    ])
    error_message = "ManageOrganisationPolicies must be limited to <name_root>-* policies"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(module.apply.inline_policies["manage"].policy).Statement :
      s.Sid == "ManageSiteBuckets" && s.Action == "s3:*"
      && s.Resource == ["arn:aws:s3:::jwall-engineering-*", "arn:aws:s3:::jwall-engineering-*/*"]
    ])
    error_message = "ManageSiteBuckets must cover the default <name_root>-* bucket pattern and its objects"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(module.apply.inline_policies["manage"].policy).Statement :
      s.Sid == "ReadWriteOwnState" && s.Action == ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
      && s.Resource == "arn:aws:s3:::jwall-engineering-tfstate/project=infra/env=prod/infra-prod.tfstate"
    ])
    error_message = "apply role reads and writes only its own state object"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(module.apply.inline_policies["manage"].policy).Statement :
      s.Sid == "ManageHostedZone" && s.Resource == "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ"
      && contains(s.Action, "route53:ChangeResourceRecordSets")
    ])
    error_message = "ManageHostedZone must be limited to hosted_zone_arn"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(module.apply.inline_policies["manage"].policy).Statement :
      alltrue([for a in flatten([s.Action]) : !can(regex("OpenIDConnectProvider", a))])
    ])
    error_message = "the apply role must not manage the OIDC provider"
  }
}

run "custom_bucket_patterns_and_attachable_policies" {
  command = plan

  variables {
    managed_bucket_patterns = ["jwall-engineering-*", "guitar-*"]
    attachable_policy_arns  = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  }

  assert {
    condition = anytrue([
      for s in jsondecode(module.apply.inline_policies["manage"].policy).Statement :
      s.Sid == "ManageSiteBuckets" && s.Resource == [
        "arn:aws:s3:::jwall-engineering-*",
        "arn:aws:s3:::jwall-engineering-*/*",
        "arn:aws:s3:::guitar-*",
        "arn:aws:s3:::guitar-*/*",
      ]
    ])
    error_message = "every managed bucket pattern must cover the bucket and its objects"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(module.apply.inline_policies["manage"].policy).Statement :
      s.Sid == "AttachAllowListedPolicies" && s.Condition.ArnLike["iam:PolicyARN"] == "arn:aws:iam::aws:policy/ReadOnlyAccess"
    ])
    error_message = "attachable_policy_arns must replace the default allow-list"
  }
}

run "trusts_only_classic_subjects_without_ids" {
  command = plan

  variables {
    owner_id      = null
    repository_id = null
  }

  assert {
    condition     = jsondecode(module.plan.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == ["repo:jwallace145/jwall-engineering-infra:pull_request"]
    error_message = "without IDs only the classic subject is trusted"
  }
}

run "rejects_state_key_with_leading_slash" {
  command = plan

  variables {
    state_key = "/project=infra/env=prod/infra-prod.tfstate"
  }

  expect_failures = [var.state_key]
}

run "rejects_bad_hosted_zone_arn" {
  command = plan

  variables {
    hosted_zone_arn = "Z0123456789ABCDEFGHIJ"
  }

  expect_failures = [var.hosted_zone_arn]
}

run "rejects_state_bucket_arn_with_path" {
  command = plan

  variables {
    state_bucket_arn = "arn:aws:s3:::jwall-engineering-tfstate/*"
  }

  expect_failures = [var.state_bucket_arn]
}

run "rejects_too_long_role_names" {
  command = plan

  variables {
    name_root = "a-very-long-organisation-name-root"
    project   = "and-an-equally-long-project-name"
  }

  expect_failures = [var.project]
}
