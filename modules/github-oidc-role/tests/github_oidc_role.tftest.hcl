mock_provider "aws" {}

variables {
  name              = "jwall-engineering-example-ci-apply"
  description       = "terraform apply for jwallace145/example releases (prod environment)"
  repository        = "jwallace145/example"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  subjects          = ["pull_request", "environment:prod"]
  component         = "ci"

  inline_policies = {
    state = {
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "ListOwnStatePrefix"
          Effect   = "Allow"
          Action   = "s3:ListBucket"
          Resource = "arn:aws:s3:::jwall-engineering-tfstate"
          Condition = {
            StringLike = {
              "s3:prefix" = "project=example/*"
            }
          }
        },
      ]
    }
    manage = {
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "ReadRoute53Changes"
          Effect   = "Allow"
          Action   = "route53:GetChange"
          Resource = "arn:aws:route53:::change/*"
        },
      ]
    }
  }

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
    "arn:aws:iam::123456789012:policy/jwall-engineering-extra",
  ]
}

run "role_identity_and_tags" {
  command = plan

  assert {
    condition     = aws_iam_role.this.name == "jwall-engineering-example-ci-apply"
    error_message = "role name must be var.name"
  }

  assert {
    condition     = aws_iam_role.this.description == var.description
    error_message = "role description must be var.description"
  }

  assert {
    condition     = aws_iam_role.this.max_session_duration == 3600
    error_message = "max_session_duration must default to 3600"
  }

  assert {
    condition     = aws_iam_role.this.tags == tomap({ Component = "ci" })
    error_message = "without name_tag the only tag set by the module is Component"
  }
}

run "name_tag_when_requested" {
  command = plan

  variables {
    name_tag = "jwall-engineering-example-ci-apply"
  }

  assert {
    condition     = aws_iam_role.this.tags == tomap({ Name = "jwall-engineering-example-ci-apply", Component = "ci" })
    error_message = "with name_tag set the role carries Name and Component"
  }
}

run "trust_policy_without_ids" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_iam_role.this.assume_role_policy).Statement) == 1
    error_message = "trust policy must have exactly one statement"
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Sid == "GitHubOidc" &&
      jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Effect == "Allow" &&
      jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity" &&
      jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.Federated == var.oidc_provider_arn
    )
    error_message = "trust statement must be sts:AssumeRoleWithWebIdentity from the OIDC provider with Sid GitHubOidc"
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    error_message = "trust policy must pin aud to sts.amazonaws.com"
  }

  assert {
    condition = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == [
      "repo:jwallace145/example:pull_request",
      "repo:jwallace145/example:environment:prod",
    ]
    error_message = "without IDs the sub list is the classic prefix joined to each subject suffix, in order"
  }
}

run "trust_policy_with_ids" {
  command = plan

  variables {
    owner_id      = "35950238"
    repository_id = "1420037633"
  }

  assert {
    condition = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == [
      "repo:jwallace145/example:pull_request",
      "repo:jwallace145/example:environment:prod",
      "repo:jwallace145@35950238/example@1420037633:pull_request",
      "repo:jwallace145@35950238/example@1420037633:environment:prod",
    ]
    error_message = "with IDs the sub list is every prefix (classic, then immutable) joined to every subject suffix"
  }
}

run "custom_trust_statement_sid" {
  command = plan

  variables {
    trust_statement_sid = "GitHubProdEnvironment"
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Sid == "GitHubProdEnvironment"
    error_message = "trust_statement_sid must set the trust statement Sid"
  }
}

run "inline_policies" {
  command = plan

  assert {
    condition     = keys(aws_iam_role_policy.this) == ["manage", "state"]
    error_message = "one aws_iam_role_policy.this per inline_policies key"
  }

  assert {
    condition = (
      aws_iam_role_policy.this["state"].name == "jwall-engineering-example-ci-apply-state" &&
      aws_iam_role_policy.this["manage"].name == "jwall-engineering-example-ci-apply-manage"
    )
    error_message = "inline policy names must be <role name>-<key>"
  }

  assert {
    condition = (
      jsondecode(aws_iam_role_policy.this["state"].policy).Statement[0].Sid == "ListOwnStatePrefix" &&
      jsondecode(aws_iam_role_policy.this["state"].policy).Statement[0].Condition.StringLike["s3:prefix"] == "project=example/*" &&
      jsondecode(aws_iam_role_policy.this["manage"].policy).Statement[0].Sid == "ReadRoute53Changes"
    )
    error_message = "each inline policy must be the jsonencode of its input document"
  }
}

run "managed_policy_attachments" {
  command = plan

  assert {
    condition = keys(aws_iam_role_policy_attachment.this) == [
      "arn:aws:iam::123456789012:policy/jwall-engineering-extra",
      "arn:aws:iam::aws:policy/ReadOnlyAccess",
    ]
    error_message = "one aws_iam_role_policy_attachment.this per managed ARN, keyed by the ARN"
  }

  assert {
    condition = alltrue([
      for arn, a in aws_iam_role_policy_attachment.this : a.policy_arn == arn
    ])
    error_message = "every attachment must attach the ARN it is keyed by"
  }
}

run "no_attachments_by_default" {
  command = plan

  variables {
    managed_policy_arns = []
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.this) == 0
    error_message = "managed_policy_arns defaults to none"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.keyed) == 0
    error_message = "managed_policies defaults to none"
  }
}

run "keyed_managed_policy_attachments" {
  command = plan

  variables {
    managed_policy_arns = []
    managed_policies = {
      "static-site/read" = "arn:aws:iam::123456789012:policy/jwall-engineering-guitar-ci-plan-static-site-read"
      "tfstate/read"     = "arn:aws:iam::123456789012:policy/jwall-engineering-guitar-ci-plan-tfstate-read"
    }
  }

  assert {
    condition     = keys(aws_iam_role_policy_attachment.keyed) == ["static-site/read", "tfstate/read"]
    error_message = "one aws_iam_role_policy_attachment.keyed per managed_policies entry, keyed by its name"
  }

  assert {
    condition = alltrue([
      for k, a in aws_iam_role_policy_attachment.keyed : a.policy_arn == var.managed_policies[k]
    ])
    error_message = "every keyed attachment must attach the ARN under its key"
  }

  assert {
    condition     = jsonencode(output.managed_policies) == jsonencode(var.managed_policies)
    error_message = "managed_policies output must map each key to its attached ARN"
  }
}

run "rejects_non_policy_arn_in_managed_policies" {
  command = plan

  variables {
    managed_policies = { bad = "arn:aws:iam::123456789012:role/not-a-policy" }
  }

  expect_failures = [var.managed_policies]
}

run "rejects_empty_subjects" {
  command = plan

  variables {
    subjects = []
  }

  expect_failures = [var.subjects]
}

run "rejects_subject_with_leading_colon" {
  command = plan

  variables {
    subjects = [":pull_request"]
  }

  expect_failures = [var.subjects]
}

run "rejects_owner_id_without_repository_id" {
  command = plan

  variables {
    owner_id = "35950238"
  }

  expect_failures = [var.owner_id]
}

run "rejects_non_numeric_repository_id" {
  command = plan

  variables {
    owner_id      = "35950238"
    repository_id = "example"
  }

  expect_failures = [var.repository_id]
}

run "rejects_bad_repository" {
  command = plan

  variables {
    repository = "not-a-repo"
  }

  expect_failures = [var.repository]
}

run "rejects_wrong_oidc_provider" {
  command = plan

  variables {
    oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/accounts.google.com"
  }

  expect_failures = [var.oidc_provider_arn]
}

# terraform test cannot address resources inside a child module, so composing
# modules (ci-plan-role, ci-preview-role, ci-apply-role) test the role through these outputs.
run "outputs_expose_role_policies_for_composing_modules" {
  command = plan

  assert {
    condition     = output.assume_role_policy == aws_iam_role.this.assume_role_policy
    error_message = "assume_role_policy output must be the role's trust policy JSON"
  }

  assert {
    condition     = output.tags == aws_iam_role.this.tags
    error_message = "tags output must be the tags the module sets on the role"
  }

  assert {
    condition = (
      keys(output.inline_policies) == ["manage", "state"] &&
      output.inline_policies["state"].name == "jwall-engineering-example-ci-apply-state" &&
      output.inline_policies["state"].policy == aws_iam_role_policy.this["state"].policy
    )
    error_message = "inline_policies output must map each key to the policy's name and JSON document"
  }

  assert {
    condition = output.managed_policy_arns == tolist([
      "arn:aws:iam::123456789012:policy/jwall-engineering-extra",
      "arn:aws:iam::aws:policy/ReadOnlyAccess",
    ])
    error_message = "managed_policy_arns output must list the attached ARNs"
  }
}
