mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  name       = "jwall-engineering-guitar-ci-plan-static-site-read"
  project    = "guitar"
  bucket_arn = "arn:aws:s3:::jwall-engineering-guitar"
  zone_id    = "Z0123456789ABCDEFGHIJ"
}

run "read_only_and_project_scoped" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for s in jsondecode(aws_iam_policy.this.policy).Statement : [
        for a in flatten([s.Action]) : can(regex("^[a-z0-9]+:(Get|List|Describe)", a))
      ]
    ]))
    error_message = "static-site/read must grant only Get*, List* and Describe* actions"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_policy.this.policy).Statement :
      try(s.Condition.StringEquals["aws:ResourceTag/Project"], null) == "guitar"
      if contains(["ReadProjectDistributions", "ReadProjectFunctions", "ReadProjectCertificates"], s.Sid)
    ])
    error_message = "distribution, function and certificate reads must be conditioned on Project = <project>"
  }

  assert {
    condition = (
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "ReadProjectFunctions"][0] == "arn:aws:cloudfront::123456789012:function/jwall-engineering-guitar-*" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "ReadHostedZone"][0] == "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ" &&
      [for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Resource if s.Sid == "ReadSiteBucketConfig"][0] == "arn:aws:s3:::jwall-engineering-guitar"
    )
    error_message = "functions, the zone and the bucket must be scoped by name"
  }

  assert {
    condition = sort([
      for s in jsondecode(aws_iam_policy.this.policy).Statement : s.Sid if s.Resource == "*"
    ]) == tolist(["ListCloudFrontAndAcm", "ReadUntaggableCloudFrontResources"])
    error_message = "only the documented gaps may use Resource = *"
  }
}
