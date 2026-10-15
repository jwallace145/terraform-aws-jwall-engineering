mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::jwall-engineering-guitar"
    }
  }
}

variables {
  project = "guitar"
}

run "bucket_name_and_tags" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "jwall-engineering-guitar"
    error_message = "bucket must be named jwall-engineering-<project>"
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Component"] == "site-bucket"
    error_message = "bucket must carry Component = site-bucket"
  }

  assert {
    condition     = output.name == "jwall-engineering-guitar"
    error_message = "name output must be the bucket name"
  }
}

run "hardening" {
  command = plan

  assert {
    condition = (
      aws_s3_bucket_public_access_block.this.block_public_acls &&
      aws_s3_bucket_public_access_block.this.block_public_policy &&
      aws_s3_bucket_public_access_block.this.ignore_public_acls &&
      aws_s3_bucket_public_access_block.this.restrict_public_buckets
    )
    error_message = "all four Block Public Access settings must be on"
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.this.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "object ownership must be BucketOwnerEnforced"
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "encryption must be SSE-S3 (AES256)"
  }

  assert {
    condition     = one(aws_s3_bucket_versioning.this.versioning_configuration).status == "Enabled"
    error_message = "versioning must be enabled"
  }
}

run "lifecycle_rules" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule) == 3
    error_message = "expected exactly three lifecycle rules"
  }

  assert {
    condition = anytrue([
      for r in aws_s3_bucket_lifecycle_configuration.this.rule :
      r.id == "expire-noncurrent-versions" && r.status == "Enabled" && one(r.noncurrent_version_expiration).noncurrent_days == 30
    ])
    error_message = "noncurrent versions must expire after 30 days"
  }

  assert {
    condition = anytrue([
      for r in aws_s3_bucket_lifecycle_configuration.this.rule :
      r.id == "expire-previews" && r.status == "Enabled" && one(r.filter).prefix == "previews/" && one(r.expiration).days == 14
    ])
    error_message = "objects under previews/ must expire after 14 days"
  }

  assert {
    condition = anytrue([
      for r in aws_s3_bucket_lifecycle_configuration.this.rule :
      r.id == "abort-incomplete-multipart-uploads" && r.status == "Enabled" && one(r.abort_incomplete_multipart_upload).days_after_initiation == 7
    ])
    error_message = "incomplete multipart uploads must be aborted after 7 days"
  }
}

run "bucket_policy" {
  command = plan

  assert {
    condition = anytrue([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement :
      s.Effect == "Deny" && s.Principal == "*" && s.Action == "s3:*" && s.Condition.Bool["aws:SecureTransport"] == "false"
      && contains(s.Resource, "arn:aws:s3:::jwall-engineering-guitar") && contains(s.Resource, "arn:aws:s3:::jwall-engineering-guitar/*")
    ])
    error_message = "policy must deny every non-TLS request on the bucket and its objects"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement :
      s.Effect == "Allow" && s.Principal.Service == "cloudfront.amazonaws.com" && s.Action == "s3:GetObject"
      && s.Resource == "arn:aws:s3:::jwall-engineering-guitar/*"
      && s.Condition.StringEquals["AWS:SourceAccount"] == "123456789012"
    ])
    error_message = "policy must allow cloudfront.amazonaws.com s3:GetObject on bucket/* conditioned on AWS:SourceAccount"
  }

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.this.policy).Statement) == 2
    error_message = "policy must contain exactly the deny-insecure and allow-cloudfront statements"
  }
}

run "rejects_non_kebab_project" {
  command = plan

  variables {
    project = "My_Project"
  }

  expect_failures = [var.project]
}

# --- Hardened policy ----------------------------------------------------------

run "hardened_policy" {
  command = plan

  variables {
    admin_principal_arns = [
      "arn:aws:iam::123456789012:user/admin",
      "arn:aws:iam::123456789012:role/jwall-engineering-infra-ci-apply",
    ]
    prefix_writers = {
      "prod/"     = ["arn:aws:iam::123456789012:role/jwall-engineering-guitar-ci-apply"]
      "dev/"      = ["arn:aws:iam::123456789012:role/jwall-engineering-guitar-ci-apply"]
      "previews/" = ["arn:aws:iam::123456789012:role/jwall-engineering-guitar-ci-preview"]
    }
  }

  assert {
    condition = [for s in jsondecode(output.policy).Statement : s.Sid] == [
      "DenyInsecureTransport",
      "AllowCloudFrontServicePrincipalRead",
      "DenyWritesOutsidePrefixes",
      "DenyWritesToPrefix0",
      "DenyWritesToPrefix1",
      "DenyWritesToPrefix2",
      "DenyUnmanagedConfiguration",
    ]
    error_message = "the hardened policy must keep the TLS and CloudFront statements and add exactly the documented denies"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(output.policy).Statement : s.Effect == "Deny" && s.Principal == "*"
      if s.Sid != "AllowCloudFrontServicePrincipalRead"
    ])
    error_message = "every hardening statement must be a Deny for Principal = *"
  }

  assert {
    condition = alltrue(flatten([
      for s in jsondecode(output.policy).Statement : [
        for a in flatten([s.Action]) : !startswith(a, "s3:GetObject")
      ] if startswith(s.Sid, "DenyWrites")
    ]))
    error_message = "write denies must never block reads; CloudFront and refresh must keep working"
  }

  assert {
    condition = jsonencode([for s in jsondecode(output.policy).Statement : s if s.Sid == "DenyWritesOutsidePrefixes"][0].NotResource) == jsonencode([
      "arn:aws:s3:::jwall-engineering-guitar/dev/*",
      "arn:aws:s3:::jwall-engineering-guitar/previews/*",
      "arn:aws:s3:::jwall-engineering-guitar/prod/*",
    ])
    error_message = "outside the declared prefixes only admins may write"
  }

  assert {
    condition = (
      [for s in jsondecode(output.policy).Statement : s if s.Sid == "DenyWritesToPrefix1"][0].Resource == "arn:aws:s3:::jwall-engineering-guitar/previews/*" &&
      jsonencode([for s in jsondecode(output.policy).Statement : s if s.Sid == "DenyWritesToPrefix1"][0].Condition.ArnNotEquals["aws:PrincipalArn"]) == jsonencode([
        "arn:aws:iam::123456789012:role/jwall-engineering-guitar-ci-preview",
        "arn:aws:iam::123456789012:user/admin",
        "arn:aws:iam::123456789012:role/jwall-engineering-infra-ci-apply",
      ])
    )
    error_message = "only the preview role and admins may write previews/"
  }

  assert {
    condition     = jsonencode([for s in jsondecode(output.policy).Statement : s if s.Sid == "DenyUnmanagedConfiguration"][0].Condition.ArnNotEquals["aws:PrincipalArn"]) == jsonencode(var.admin_principal_arns)
    error_message = "only admins may change bucket configuration, including the bucket policy"
  }
}

run "rejects_prefix_writers_without_admins" {
  command = plan

  variables {
    prefix_writers = { "prod/" = ["arn:aws:iam::123456789012:role/a"] }
  }

  expect_failures = [var.prefix_writers]
}

run "rejects_prefix_without_trailing_slash" {
  command = plan

  variables {
    admin_principal_arns = ["arn:aws:iam::123456789012:user/admin"]
    prefix_writers       = { "prod" = ["arn:aws:iam::123456789012:role/a"] }
  }

  expect_failures = [var.prefix_writers]
}

run "rejects_overlapping_prefixes" {
  command = plan

  variables {
    admin_principal_arns = ["arn:aws:iam::123456789012:user/admin"]
    prefix_writers = {
      "previews/"      = ["arn:aws:iam::123456789012:role/a"]
      "previews/pr-1/" = ["arn:aws:iam::123456789012:role/b"]
    }
  }

  expect_failures = [var.prefix_writers]
}

run "rejects_wildcard_principal" {
  command = plan

  variables {
    admin_principal_arns = ["arn:aws:iam::123456789012:role/*"]
  }

  expect_failures = [var.admin_principal_arns]
}
