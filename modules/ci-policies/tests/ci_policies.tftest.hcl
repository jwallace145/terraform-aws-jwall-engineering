mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
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
  role              = "apply"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  policies          = ["tfstate/write", "static-site/read", "static-site/deploy"]

  policy_inputs = {
    tfstate = {
      bucket_arn = "arn:aws:s3:::jwall-engineering-tfstate"
      prefix     = "project=guitar/"
    }
    static_site = {
      bucket_arn = "arn:aws:s3:::jwall-engineering-guitar"
      zone_id    = "Z0123456789ABCDEFGHIJ"
      record_names = [
        "guitar.jwall.engineering",
        "dev.guitar.jwall.engineering",
        "*.preview.guitar.jwall.engineering",
      ]
    }
    foundation = {
      state_bucket_arn = "arn:aws:s3:::jwall-engineering-tfstate"
      hosted_zone_arn  = "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ"
    }
  }
}

run "creates_only_requested_policies" {
  command = plan

  assert {
    condition = (
      length(module.tfstate_read) == 0 &&
      length(module.tfstate_write) == 1 &&
      length(module.static_site_read) == 1 &&
      length(module.static_site_deploy) == 1 &&
      length(module.static_site_previews) == 0 &&
      length(module.foundation_read) == 0 &&
      length(module.foundation_manage) == 0
    )
    error_message = "exactly the requested policies must be created"
  }

  assert {
    condition     = jsonencode(sort(keys(output.arns))) == jsonencode(["static-site/deploy", "static-site/read", "tfstate/write"])
    error_message = "arns must be keyed by the requested policy names"
  }

  assert {
    condition = jsonencode(output.names) == jsonencode({
      "static-site/deploy" = "jwall-engineering-guitar-ci-apply-static-site-deploy"
      "static-site/read"   = "jwall-engineering-guitar-ci-apply-static-site-read"
      "tfstate/write"      = "jwall-engineering-guitar-ci-apply-tfstate-write"
    })
    error_message = "policies must be named <name_root>-<project>-ci-<role>-<family>-<name>"
  }
}

run "every_policy_fits_the_managed_policy_size_limit" {
  command = plan

  variables {
    policies = [
      "tfstate/read",
      "tfstate/write",
      "static-site/read",
      "static-site/deploy",
      "foundation/read",
      "foundation/manage",
    ]
  }

  # IAM counts managed policy size without whitespace; jsonencode emits none.
  assert {
    condition     = alltrue([for p, d in output.documents : length(d) <= 6144])
    error_message = "every policy document must fit IAM's 6,144-character managed policy limit"
  }

  assert {
    condition     = length(output.documents) == 6
    error_message = "every requested policy must produce a document"
  }
}

run "preview_role_accepts_previews" {
  command = plan

  variables {
    role     = "preview"
    policies = ["static-site/previews"]
  }

  assert {
    condition     = output.names["static-site/previews"] == "jwall-engineering-guitar-ci-preview-static-site-previews"
    error_message = "the preview role must accept static-site/previews"
  }
}

run "plan_role_accepts_read_policies" {
  command = plan

  variables {
    role     = "plan"
    policies = ["tfstate/read", "static-site/read", "foundation/read"]
  }

  assert {
    condition     = length(output.arns) == 3
    error_message = "the plan role must accept every read policy"
  }
}

run "plan_role_rejects_write_policies" {
  command = plan

  variables {
    role     = "plan"
    policies = ["tfstate/read", "static-site/deploy"]
  }

  expect_failures = [var.policies]
}

run "plan_role_rejects_previews" {
  command = plan

  variables {
    role     = "plan"
    policies = ["static-site/previews"]
  }

  expect_failures = [var.policies]
}

run "preview_role_rejects_read_policies" {
  command = plan

  variables {
    role     = "preview"
    policies = ["static-site/previews", "tfstate/read"]
  }

  expect_failures = [var.policies]
}

run "apply_role_rejects_previews" {
  command = plan

  variables {
    policies = ["static-site/previews"]
  }

  expect_failures = [var.policies]
}

run "rejects_unknown_policy" {
  command = plan

  variables {
    policies = ["tfstate/read", "s3/everything"]
  }

  expect_failures = [var.policies]
}

run "rejects_empty_policies" {
  command = plan

  variables {
    policies = []
  }

  expect_failures = [var.policies]
}

run "rejects_tfstate_without_inputs" {
  command = plan

  variables {
    policies = ["tfstate/write"]
    policy_inputs = {
      foundation = {
        state_bucket_arn = "arn:aws:s3:::jwall-engineering-tfstate"
        hosted_zone_arn  = "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ"
      }
    }
  }

  expect_failures = [var.policies]
}

run "rejects_static_site_without_inputs" {
  command = plan

  variables {
    role          = "preview"
    policies      = ["static-site/previews"]
    policy_inputs = {}
  }

  expect_failures = [var.policies]
}

run "previews_need_only_the_bucket" {
  command = plan

  variables {
    role     = "preview"
    policies = ["static-site/previews"]
    policy_inputs = {
      static_site = { bucket_arn = "arn:aws:s3:::jwall-engineering-guitar" }
    }
  }

  assert {
    condition     = length(module.static_site_previews) == 1
    error_message = "static-site/previews must not require zone_id or record_names"
  }
}

run "rejects_static_site_read_without_zone" {
  command = plan

  variables {
    role     = "plan"
    policies = ["static-site/read"]
    policy_inputs = {
      static_site = { bucket_arn = "arn:aws:s3:::jwall-engineering-guitar" }
    }
  }

  expect_failures = [var.policies]
}

run "rejects_static_site_deploy_without_record_names" {
  command = plan

  variables {
    policies = ["static-site/deploy"]
    policy_inputs = {
      static_site = {
        bucket_arn = "arn:aws:s3:::jwall-engineering-guitar"
        zone_id    = "Z0123456789ABCDEFGHIJ"
      }
    }
  }

  expect_failures = [var.policies]
}

run "rejects_foundation_without_inputs" {
  command = plan

  variables {
    policies      = ["foundation/manage"]
    policy_inputs = {}
  }

  expect_failures = [var.policies]
}

run "rejects_role_outside_the_catalog" {
  command = plan

  variables {
    role = "deploy"
  }

  expect_failures = [var.role]
}
