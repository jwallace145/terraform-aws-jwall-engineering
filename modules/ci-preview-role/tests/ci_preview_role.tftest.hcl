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
  policies          = ["static-site/previews"]

  policy_inputs = {
    static_site = { bucket_arn = "arn:aws:s3:::jwall-engineering-guitar" }
  }
}

run "role_identity" {
  command = plan

  assert {
    condition     = module.role.name == "jwall-engineering-guitar-ci-preview"
    error_message = "the role must be named <name_root>-<project>-ci-preview"
  }

  assert {
    condition     = module.role.tags == tomap({ Component = "ci", Name = "jwall-engineering-guitar-ci-preview" })
    error_message = "the role must carry Component = ci and Name = <role name>"
  }

  assert {
    condition     = output.role_name == module.role.name && output.role_arn == module.role.arn
    error_message = "role_name and role_arn must expose the role"
  }
}

run "trusts_pull_requests_only" {
  command = plan

  assert {
    condition     = jsondecode(module.role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == ["repo:jwallace145/guitar:pull_request"]
    error_message = "the preview role must trust only pull_request"
  }

  assert {
    condition     = jsondecode(module.role.assume_role_policy).Statement[0].Sid == "GitHubPullRequests"
    error_message = "the trust statement Sid must be GitHubPullRequests"
  }
}

run "attaches_previews_policy" {
  command = plan

  assert {
    condition     = jsonencode(keys(module.role.managed_policies)) == jsonencode(["static-site/previews"])
    error_message = "static-site/previews must be attached, keyed by its catalog name"
  }

  assert {
    condition     = length(module.role.inline_policies) == 0 && length(module.role.managed_policy_arns) == 0
    error_message = "the role must have no inline policies and no other managed policies"
  }
}

# expect_failures cannot reach a validation inside module.policies, so the
# allow-list itself is tested in ci-policies. This pins that the role asks the
# catalog for the preview allow-list: the role is part of every policy name.
run "requests_the_preview_allow_list" {
  command = plan

  assert {
    condition     = alltrue([for p, n in module.policies.names : startswith(n, "jwall-engineering-guitar-ci-preview-")])
    error_message = "the role must create its policies with role = preview"
  }
}
