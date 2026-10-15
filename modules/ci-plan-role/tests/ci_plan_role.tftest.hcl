mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock"
    }
  }
}

variables {
  project           = "guitar"
  repository        = "jwallace145/guitar"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  policies          = ["tfstate/read", "static-site/read"]

  policy_inputs = {
    tfstate = {
      bucket_arn = "arn:aws:s3:::jwall-engineering-tfstate"
      prefix     = "project=guitar/"
    }
    static_site = {
      bucket_arn = "arn:aws:s3:::jwall-engineering-guitar"
      zone_id    = "Z0123456789ABCDEFGHIJ"
    }
  }
}

run "role_identity" {
  command = plan

  assert {
    condition     = module.role.name == "jwall-engineering-guitar-ci-plan"
    error_message = "the role must be named <name_root>-<project>-ci-plan"
  }

  assert {
    condition     = module.role.tags == tomap({ Component = "ci", Name = "jwall-engineering-guitar-ci-plan" })
    error_message = "the role must carry Component = ci and Name = <role name>"
  }

  assert {
    condition     = output.role_name == module.role.name && output.role_arn == module.role.arn
    error_message = "role_name and role_arn must expose the role"
  }
}

run "trusts_pull_requests_only" {
  command = plan

  variables {
    owner_id      = "35950238"
    repository_id = "123456789"
  }

  assert {
    condition = jsondecode(module.role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == [
      "repo:jwallace145/guitar:pull_request",
      "repo:jwallace145@35950238/guitar@123456789:pull_request",
    ]
    error_message = "the plan role must trust only pull_request, in both subject forms"
  }

  assert {
    condition     = jsondecode(module.role.assume_role_policy).Statement[0].Sid == "GitHubPullRequests"
    error_message = "the trust statement Sid must be GitHubPullRequests"
  }
}

run "attaches_requested_policies_as_managed_policies" {
  command = plan

  assert {
    condition     = jsonencode(sort(keys(module.role.managed_policies))) == jsonencode(["static-site/read", "tfstate/read"])
    error_message = "each requested policy must be attached, keyed by its catalog name"
  }

  assert {
    condition     = length(module.role.inline_policies) == 0 && length(module.role.managed_policy_arns) == 0
    error_message = "the role must have no inline policies and no other managed policies"
  }

  assert {
    condition     = jsonencode(output.policy_arns) == jsonencode(module.role.managed_policies)
    error_message = "policy_arns must be the attached policies"
  }
}

# expect_failures cannot reach a validation inside module.policies, so the
# allow-list itself is tested in ci-policies. This pins that the role asks the
# catalog for the plan allow-list: the role is part of every policy name.
run "requests_the_plan_allow_list" {
  command = plan

  assert {
    condition     = alltrue([for p, n in module.policies.names : startswith(n, "jwall-engineering-guitar-ci-plan-")])
    error_message = "the role must create its policies with role = plan"
  }
}
