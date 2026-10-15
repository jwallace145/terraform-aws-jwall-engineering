mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  project           = "guitar"
  repository        = "jwallace145/guitar"
  bucket_arn        = "arn:aws:s3:::jwall-engineering-guitar"
  state_bucket_arn  = "arn:aws:s3:::jwall-engineering-terraform-state"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  zone_id           = "Z0123456789ABCDEFGHIJ"
  record_names = [
    "guitar.jwall.engineering",
    "dev.guitar.jwall.engineering",
    "*.preview.guitar.jwall.engineering",
  ]
}

run "role_names_and_trust" {
  command = plan

  assert {
    condition = (
      aws_iam_role.this["plan"].name == "jwall-engineering-guitar-ci-plan" &&
      aws_iam_role.this["preview"].name == "jwall-engineering-guitar-ci-preview" &&
      aws_iam_role.this["apply"].name == "jwall-engineering-guitar-ci-apply"
    )
    error_message = "roles must be named jwall-engineering-<project>-ci-{plan,preview,apply}"
  }

  assert {
    condition = alltrue([
      for k, r in aws_iam_role.this : r.tags["Component"] == "site-ci-roles"
    ])
    error_message = "every role must carry Component = site-ci-roles"
  }

  assert {
    condition = alltrue([
      for k, r in aws_iam_role.this : (
        jsondecode(r.assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity" &&
        jsondecode(r.assume_role_policy).Statement[0].Principal.Federated == var.oidc_provider_arn &&
        jsondecode(r.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
      )
    ])
    error_message = "every trust policy must be GitHub OIDC with aud = sts.amazonaws.com"
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.this["plan"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:jwallace145/guitar:pull_request" &&
      jsondecode(aws_iam_role.this["preview"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:jwallace145/guitar:pull_request" &&
      jsondecode(aws_iam_role.this["apply"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:jwallace145/guitar:environment:prod"
    )
    error_message = "sub claims must be pull_request for plan/preview and environment:prod for apply"
  }
}

run "no_role_has_iam_permissions" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for k, p in aws_iam_role_policy.this : [
        for s in jsondecode(p.policy).Statement : [
          for a in flatten([s.Action]) : !startswith(a, "iam:")
        ]
      ]
    ]))
    error_message = "no role policy may grant any iam:* action"
  }

  assert {
    condition = alltrue(flatten([
      for k, p in aws_iam_role_policy.this : [
        for s in jsondecode(p.policy).Statement : s.Effect == "Allow"
      ]
    ]))
    error_message = "policies are allow-lists only"
  }
}

run "plan_role_state_access" {
  command = plan

  assert {
    condition = anytrue([
      for s in jsondecode(aws_iam_role_policy.this["plan"].policy).Statement :
      s.Sid == "ReadProjectState" && s.Action == "s3:GetObject" && s.Resource == "arn:aws:s3:::jwall-engineering-terraform-state/project=guitar/*"
    ])
    error_message = "plan role must read state under project=<project>/*"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_iam_role_policy.this["plan"].policy).Statement :
      s.Sid == "ManageProjectStateLocks" && s.Resource == "arn:aws:s3:::jwall-engineering-terraform-state/project=guitar/*.tflock"
      && contains(s.Action, "s3:PutObject") && contains(s.Action, "s3:DeleteObject")
    ])
    error_message = "plan role must be able to Put/Delete only *.tflock objects under its state prefix"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.this["plan"].policy).Statement :
      !(contains(flatten([s.Action]), "s3:PutObject") || contains(flatten([s.Action]), "s3:DeleteObject")) || s.Sid == "ManageProjectStateLocks"
    ])
    error_message = "plan role may only write .tflock files"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.this["plan"].policy).Statement :
      alltrue([for a in flatten([s.Action]) : !can(regex("^(cloudfront|acm):(Create|Update|Delete|Tag|Untag|Request|Publish)", a))])
    ])
    error_message = "plan role must be read-only on CloudFront and ACM"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.this["plan"].policy).Statement :
      !contains(flatten([s.Action]), "route53:ChangeResourceRecordSets")
    ])
    error_message = "plan role must not change Route 53 records"
  }
}

run "preview_role_is_limited_to_previews_prefix" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_iam_role_policy.this["preview"].policy).Statement) == 2
    error_message = "preview role must have exactly the list and write statements"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_iam_role_policy.this["preview"].policy).Statement :
      s.Action == "s3:ListBucket" && s.Resource == "arn:aws:s3:::jwall-engineering-guitar" && s.Condition.StringLike["s3:prefix"] == "previews/*"
    ])
    error_message = "preview role ListBucket must be conditioned on s3:prefix previews/*"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_iam_role_policy.this["preview"].policy).Statement :
      s.Resource == "arn:aws:s3:::jwall-engineering-guitar/previews/*" && contains(s.Action, "s3:PutObject") && contains(s.Action, "s3:DeleteObject") && length(s.Action) == 2
    ])
    error_message = "preview role must only Put/Delete under previews/*"
  }
}

run "apply_role_permissions" {
  command = plan

  assert {
    condition = anytrue([
      for s in jsondecode(aws_iam_role_policy.this["apply"].policy).Statement :
      s.Sid == "ReadWriteProjectState" && s.Resource == "arn:aws:s3:::jwall-engineering-terraform-state/project=guitar/*"
      && contains(s.Action, "s3:GetObject") && contains(s.Action, "s3:PutObject") && contains(s.Action, "s3:DeleteObject")
    ])
    error_message = "apply role must read/write state under project=<project>/*"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_iam_role_policy.this["apply"].policy).Statement :
      s.Sid == "WriteSiteContent"
      && contains(s.Resource, "arn:aws:s3:::jwall-engineering-guitar/prod/*")
      && contains(s.Resource, "arn:aws:s3:::jwall-engineering-guitar/dev/*")
      && length(s.Resource) == 2
    ])
    error_message = "apply role must write only prod/* and dev/*"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.this["apply"].policy).Statement :
      !can(regex("previews", jsonencode(s.Resource)))
    ])
    error_message = "apply role must not touch previews/*"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_iam_role_policy.this["apply"].policy).Statement :
      s.Sid == "ManageProjectDistributions"
      && s.Resource == "arn:aws:cloudfront::123456789012:distribution/*"
      && s.Condition.StringEquals["aws:ResourceTag/Project"] == "guitar"
      && contains(s.Action, "cloudfront:CreateInvalidation")
      && contains(s.Action, "cloudfront:UpdateDistribution")
    ])
    error_message = "distribution management must be scoped by aws:ResourceTag/Project"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_iam_role_policy.this["apply"].policy).Statement :
      s.Sid == "CreateProjectDistributions" && s.Condition.StringEquals["aws:RequestTag/Project"] == "guitar"
      && contains(s.Action, "cloudfront:CreateDistribution") && contains(s.Action, "cloudfront:CreateFunction")
    ])
    error_message = "distribution/function creation must be scoped by aws:RequestTag/Project"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_iam_role_policy.this["apply"].policy).Statement :
      s.Sid == "ManageProjectFunctions"
      && s.Resource == "arn:aws:cloudfront::123456789012:function/jwall-engineering-guitar-*"
      && s.Condition.StringEquals["aws:ResourceTag/Project"] == "guitar"
    ])
    error_message = "function management must be scoped by name prefix and Project tag"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_iam_role_policy.this["apply"].policy).Statement :
      s.Sid == "RequestProjectCertificates" && s.Action == "acm:RequestCertificate" && s.Condition.StringEquals["aws:RequestTag/Project"] == "guitar"
      ]) && anytrue([
      for s in jsondecode(aws_iam_role_policy.this["apply"].policy).Statement :
      s.Sid == "ManageProjectCertificates"
      && s.Resource == "arn:aws:acm:us-east-1:123456789012:certificate/*"
      && s.Condition.StringEquals["aws:ResourceTag/Project"] == "guitar"
    ])
    error_message = "ACM permissions must be scoped by Project tag"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_iam_role_policy.this["apply"].policy).Statement :
      s.Action == "route53:ChangeResourceRecordSets"
      && s.Resource == "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ"
      && s.Condition["ForAllValues:StringLike"]["route53:ChangeResourceRecordSetsNormalizedRecordNames"] == [
        "guitar.jwall.engineering",
        "dev.guitar.jwall.engineering",
        "\\052.preview.guitar.jwall.engineering",
        "_*.guitar.jwall.engineering",
        "_*.dev.guitar.jwall.engineering",
        "_*.preview.guitar.jwall.engineering",
      ]
    ])
    error_message = "ChangeResourceRecordSets must be limited to the zone and the project's normalised record names (wildcard as \\052) plus ACM validation names"
  }
}

run "rejects_bad_record_name" {
  command = plan

  variables {
    record_names = ["Guitar.Example.COM."]
  }

  expect_failures = [var.record_names]
}

run "rejects_bucket_arn_with_path" {
  command = plan

  variables {
    bucket_arn = "arn:aws:s3:::jwall-engineering-guitar/*"
  }

  expect_failures = [var.bucket_arn]
}

run "rejects_wrong_oidc_provider" {
  command = plan

  variables {
    oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/accounts.google.com"
  }

  expect_failures = [var.oidc_provider_arn]
}
