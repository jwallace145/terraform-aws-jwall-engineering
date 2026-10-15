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
  project           = "infra"
  repository        = "jwallace145/jwall-engineering-infra"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  policies          = ["tfstate/write", "foundation/read", "foundation/manage"]

  policy_inputs = {
    tfstate = {
      bucket_arn = "arn:aws:s3:::jwall-engineering-tfstate"
      key        = "project=infra/env=prod/infra-prod.tfstate"
    }
    foundation = {
      state_bucket_arn = "arn:aws:s3:::jwall-engineering-tfstate"
      hosted_zone_arn  = "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ"
    }
  }
}

# Names match the roles infra-ci-roles created, so adopting them keeps their
# ARNs.
run "role_identity_matches_infra_ci_roles" {
  command = plan

  assert {
    condition     = module.role.name == "jwall-engineering-infra-ci-apply"
    error_message = "the role must be named <name_root>-<project>-ci-apply"
  }

  assert {
    condition     = local.name == "jwall-engineering-infra-ci-apply" && module.role.tags == tomap({ Component = "ci", Name = "jwall-engineering-infra-ci-apply" })
    error_message = "the role must carry Component = ci and Name = <role name>"
  }

  assert {
    condition     = output.role_name == module.role.name && output.role_arn == module.role.arn
    error_message = "role_name and role_arn must expose the role"
  }
}

run "trusts_the_environment_only" {
  command = plan

  assert {
    condition     = jsondecode(module.role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == ["repo:jwallace145/jwall-engineering-infra:environment:prod"]
    error_message = "the apply role must trust only environment:prod by default"
  }

  assert {
    condition     = jsondecode(module.role.assume_role_policy).Statement[0].Sid == "GitHubProdEnvironment"
    error_message = "the trust statement Sid must be GitHubProdEnvironment"
  }
}

run "custom_environment" {
  command = plan

  variables {
    environment = "staging-eu"
  }

  assert {
    condition     = jsondecode(module.role.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == ["repo:jwallace145/jwall-engineering-infra:environment:staging-eu"]
    error_message = "the apply role must trust environment:<environment>"
  }

  assert {
    condition     = jsondecode(module.role.assume_role_policy).Statement[0].Sid == "GitHubStagingEuEnvironment"
    error_message = "the trust statement Sid must be GitHub<Environment in PascalCase>Environment"
  }
}

run "attaches_requested_policies_as_managed_policies" {
  command = plan

  assert {
    condition     = jsonencode(sort(keys(module.role.managed_policies))) == jsonencode(["foundation/manage", "foundation/read", "tfstate/write"])
    error_message = "each requested policy must be attached, keyed by its catalog name"
  }

  assert {
    condition     = length(module.role.inline_policies) == 0 && length(module.role.managed_policy_arns) == 0
    error_message = "the role must have no inline policies and no other managed policies, ReadOnlyAccess included"
  }
}

run "accepts_static_site_policies" {
  command = plan

  variables {
    project    = "guitar"
    repository = "jwallace145/guitar"
    policies   = ["tfstate/write", "static-site/read", "static-site/deploy"]
    policy_inputs = {
      tfstate = {
        bucket_arn = "arn:aws:s3:::jwall-engineering-tfstate"
        prefix     = "project=guitar/"
      }
      static_site = {
        bucket_arn   = "arn:aws:s3:::jwall-engineering-guitar"
        zone_id      = "Z0123456789ABCDEFGHIJ"
        record_names = ["guitar.jwall.engineering"]
      }
    }
  }

  assert {
    condition     = length(module.role.managed_policies) == 3
    error_message = "the apply role must accept static-site read and write policies"
  }
}

# expect_failures cannot reach a validation inside module.policies, so the
# allow-list itself is tested in ci-policies. This pins that the role asks the
# catalog for the apply allow-list: the role is part of every policy name.
run "requests_the_apply_allow_list" {
  command = plan

  assert {
    condition     = alltrue([for p, n in module.policies.names : startswith(n, "jwall-engineering-infra-ci-apply-")])
    error_message = "the role must create its policies with role = apply"
  }
}

run "rejects_bad_environment" {
  command = plan

  variables {
    environment = "prod env"
  }

  expect_failures = [var.environment]
}
