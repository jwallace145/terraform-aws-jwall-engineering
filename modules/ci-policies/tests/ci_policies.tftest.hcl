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
    ecr = {
      repository_arn = "arn:aws:ecr:us-east-1:123456789012:repository/jwall-engineering-sites"
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
      "ecr/pull",
      "ecr/push",
      "container/read",
      "container/manage",
    ]
  }

  # IAM counts managed policy size without whitespace; jsonencode emits none.
  assert {
    condition     = alltrue([for p, d in output.documents : length(d) <= 6144])
    error_message = "every policy document must fit IAM's 6,144-character managed policy limit"
  }

  assert {
    condition     = length(output.documents) == 10
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

# --- common class: every role may pull the CI tool image ---------------------

run "every_role_accepts_ecr_pull" {
  command = plan

  variables {
    role     = "preview"
    policies = ["static-site/previews", "ecr/pull"]
  }

  assert {
    condition     = output.names["ecr/pull"] == "jwall-engineering-guitar-ci-preview-ecr-pull"
    error_message = "the preview role must accept the common policy ecr/pull"
  }
}

run "plan_role_accepts_ecr_pull" {
  command = plan

  variables {
    role     = "plan"
    policies = ["tfstate/read", "ecr/pull"]
  }

  assert {
    condition     = length(output.arns) == 2
    error_message = "the plan role must accept the common policy ecr/pull"
  }
}

run "apply_role_accepts_ecr_push" {
  command = plan

  variables {
    policies = ["foundation/manage", "ecr/push"]
  }

  assert {
    condition     = output.names["ecr/push"] == "jwall-engineering-guitar-ci-apply-ecr-push"
    error_message = "the apply role must accept the write policy ecr/push"
  }
}

run "plan_role_rejects_ecr_push" {
  command = plan

  variables {
    role     = "plan"
    policies = ["ecr/push"]
  }

  expect_failures = [var.policies]
}

run "preview_role_rejects_ecr_push" {
  command = plan

  variables {
    role     = "preview"
    policies = ["ecr/push"]
  }

  expect_failures = [var.policies]
}

run "rejects_ecr_without_inputs" {
  command = plan

  variables {
    role          = "preview"
    policies      = ["ecr/pull"]
    policy_inputs = {}
  }

  expect_failures = [var.policies]
}

# -- container/* and the release role ------------------------------------------

run "release_role_accepts_only_release_and_common" {
  command = plan

  variables {
    role     = "release"
    project  = "rusty-chess"
    policies = ["container/release", "ecr/pull"]
  }

  assert {
    condition     = jsonencode(sort(keys(output.names))) == jsonencode(["container/release", "ecr/pull"])
    error_message = "the release role must get exactly the requested policies"
  }

  assert {
    condition     = output.names["container/release"] == "jwall-engineering-rusty-chess-ci-release-container-release"
    error_message = "release policies are named <name_root>-<project>-ci-release-<family>-<name>"
  }
}

run "release_role_rejects_write" {
  command = plan

  variables {
    role     = "release"
    policies = ["container/manage"]
  }

  expect_failures = [var.policies]
}

run "release_role_rejects_read" {
  command = plan

  variables {
    role     = "release"
    policies = ["container/read"]
  }

  expect_failures = [var.policies]
}

run "apply_role_accepts_container_manage" {
  command = plan

  variables {
    project  = "rusty-chess"
    policies = ["container/read", "container/manage"]
    policy_inputs = {
      container = {
        attachable_policy_arns = ["arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"]
      }
    }
  }

  assert {
    condition     = length(module.container_read) == 1 && length(module.container_manage) == 1 && length(module.container_release) == 0
    error_message = "the apply role gets container/read and container/manage"
  }

  assert {
    condition     = strcontains(output.documents["container/manage"], "CloudWatchAgentServerPolicy")
    error_message = "policy_inputs.container.attachable_policy_arns must reach container/manage"
  }
}

run "plan_role_accepts_container_read" {
  command = plan

  variables {
    role     = "plan"
    project  = "rusty-chess"
    policies = ["container/read"]
  }

  assert {
    condition     = output.names["container/read"] == "jwall-engineering-rusty-chess-ci-plan-container-read"
    error_message = "the plan role gets container/read"
  }
}

run "apply_role_rejects_container_release" {
  command = plan

  variables {
    policies = ["container/release"]
  }

  expect_failures = [var.policies]
}
