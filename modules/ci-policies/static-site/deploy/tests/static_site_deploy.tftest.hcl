mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  name       = "jwall-engineering-guitar-ci-apply-static-site-deploy"
  project    = "guitar"
  bucket_arn = "arn:aws:s3:::jwall-engineering-guitar"
  zone_id    = "Z0123456789ABCDEFGHIJ"
  record_names = [
    "guitar.jwall.engineering",
    "dev.guitar.jwall.engineering",
    "*.preview.guitar.jwall.engineering",
  ]
}

run "records_are_limited_to_the_project" {
  command = plan

  assert {
    condition = [
      for s in jsondecode(aws_iam_policy.this.policy).Statement :
      s.Condition["ForAllValues:StringLike"]["route53:ChangeResourceRecordSetsNormalizedRecordNames"]
      if s.Sid == "ChangeProjectRecords"
      ][0] == [
      "guitar.jwall.engineering",
      "dev.guitar.jwall.engineering",
      "\\052.preview.guitar.jwall.engineering",
      "_*.guitar.jwall.engineering",
      "_*.dev.guitar.jwall.engineering",
      "_*.preview.guitar.jwall.engineering",
    ]
    error_message = "record changes must be limited to record_names (wildcards as \\052) and their ACM validation names"
  }
}

run "content_writes_are_limited_to_prod_and_dev" {
  command = plan

  assert {
    condition = [for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "WriteSiteContent"][0] == [
      "arn:aws:s3:::jwall-engineering-guitar/prod/*",
      "arn:aws:s3:::jwall-engineering-guitar/dev/*",
    ]
    error_message = "content writes must be limited to prod/ and dev/"
  }
}

run "creates_and_manages_only_tagged_resources" {
  command = plan

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_policy.this.policy).Statement :
      try(s.Condition.StringEquals["aws:RequestTag/Project"], null) == "guitar"
      if contains(["CreateProjectDistributions", "RequestProjectCertificates"], s.Sid)
    ])
    error_message = "create actions must require the Project request tag"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_policy.this.policy).Statement :
      try(s.Condition.StringEquals["aws:ResourceTag/Project"], null) == "guitar"
      if contains(["ManageProjectDistributions", "ManageProjectFunctions", "ManageProjectCertificates"], s.Sid)
    ])
    error_message = "manage actions must require the Project resource tag"
  }

  assert {
    condition = sort([
      for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Sid if s.Resource == "*" && !can(s.Condition)
    ]) == tolist(["ManageUntaggableCloudFrontResources"])
    error_message = "only the documented untaggable-resource gap may use an unconditioned Resource = *"
  }
}

run "rejects_uppercase_record_name" {
  command = plan

  variables {
    record_names = ["Guitar.jwall.engineering"]
  }

  expect_failures = [var.record_names]
}

# `description` forces replacement of the policy, which would detach it from
# every role mid-apply. It is frozen; change the README instead.
run "description_is_frozen" {
  command = plan

  assert {
    condition     = aws_iam_policy.this.description == "CI policy static-site/deploy: manage the project's distributions, functions, certificates and records, and publish prod/ and dev/"
    error_message = "the policy description must never change: it forces replacement"
  }
}
