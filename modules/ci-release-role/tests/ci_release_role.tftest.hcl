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
  project           = "rusty-chess"
  repository        = "jwallace145/rusty-chess-v2"
  owner_id          = "35950238"
  repository_id     = "100"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  policies          = ["container/release"]
}

run "role_identity" {
  command = plan

  assert {
    condition     = module.role.name == "jwall-engineering-rusty-chess-ci-release"
    error_message = "the role must be named <name_root>-<project>-ci-release"
  }

  assert {
    condition     = module.role.tags == tomap({ Component = "ci", Name = "jwall-engineering-rusty-chess-ci-release" })
    error_message = "the role must carry Component = ci and Name = <role name>"
  }

  assert {
    condition     = output.role_name == module.role.name && output.role_arn == module.role.arn
    error_message = "role_name and role_arn must expose the role"
  }
}

run "trusts_release_tags_only" {
  command = plan

  assert {
    condition = jsonencode(jsondecode(module.role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]) == jsonencode([
      "repo:jwallace145/rusty-chess-v2:ref:refs/tags/v*",
      "repo:jwallace145@35950238/rusty-chess-v2@100:ref:refs/tags/v*",
    ])
    error_message = "the role must trust only the repository's v* release tags, classic and immutable subjects"
  }

  assert {
    condition = (
      jsondecode(module.role.assume_role_policy).Statement[0].Sid == "GitHubReleaseTags" &&
      jsondecode(module.role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    )
    error_message = "trust statement Sid GitHubReleaseTags with the STS audience"
  }

  assert {
    condition = !anytrue([
      for s in jsondecode(module.role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] :
      can(regex("pull_request|environment|refs/heads", s))
    ])
    error_message = "no branch, pull request or environment subject may assume the release role"
  }
}

run "custom_tag_pattern" {
  command = plan

  variables {
    tag_pattern = "release-*"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(module.role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] :
      endswith(s, ":ref:refs/tags/release-*")
    ])
    error_message = "tag_pattern sets the trusted tag glob"
  }
}

run "policies_come_from_the_catalog" {
  command = plan

  assert {
    condition     = module.policies.names["container/release"] == "jwall-engineering-rusty-chess-ci-release-container-release"
    error_message = "the release policy comes from ci-policies with role = release"
  }
}

run "rejects_write_policies" {
  command = plan

  variables {
    policies = ["container/manage"]
  }

  expect_failures = [var.policies]
}

run "rejects_bad_tag_pattern" {
  command = plan

  variables {
    tag_pattern = "v*/../*"
  }

  expect_failures = [var.tag_pattern]
}
