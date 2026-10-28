mock_provider "aws" {
  override_during = plan

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::jwall-engineering-rusty-chess-records"
    }
  }
}

variables {
  name = "jwall-engineering-rusty-chess-records"
}

run "bucket_hardening" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "jwall-engineering-rusty-chess-records"
    error_message = "bucket name must be var.name"
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "versioning must be enabled"
  }

  assert {
    condition = (
      tolist(aws_s3_bucket_server_side_encryption_configuration.this.rule)[0].apply_server_side_encryption_by_default[0].sse_algorithm == "AES256" &&
      tolist(aws_s3_bucket_server_side_encryption_configuration.this.rule)[0].bucket_key_enabled == true
    )
    error_message = "objects must be encrypted with SSE-S3 and a bucket key"
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.this.block_public_acls &&
      aws_s3_bucket_public_access_block.this.block_public_policy &&
      aws_s3_bucket_public_access_block.this.ignore_public_acls &&
      aws_s3_bucket_public_access_block.this.restrict_public_buckets
    )
    error_message = "all four public access blocks must be on"
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.this.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "object ownership must be BucketOwnerEnforced"
  }

  assert {
    condition     = aws_s3_bucket.this.tags == tomap({ Name = "jwall-engineering-rusty-chess-records", Component = "private-bucket" })
    error_message = "the bucket must carry Name and Component tags only"
  }
}

run "lifecycle_defaults" {
  command = plan

  assert {
    condition = (
      aws_s3_bucket_lifecycle_configuration.this.rule[0].id == "expire-noncurrent-versions" &&
      aws_s3_bucket_lifecycle_configuration.this.rule[0].status == "Enabled" &&
      aws_s3_bucket_lifecycle_configuration.this.rule[0].noncurrent_version_expiration[0].noncurrent_days == 30 &&
      aws_s3_bucket_lifecycle_configuration.this.rule[0].filter[0].prefix == ""
    )
    error_message = "rule 0 must expire noncurrent versions after 30 days by default, for every key"
  }

  assert {
    condition = (
      aws_s3_bucket_lifecycle_configuration.this.rule[1].id == "abort-incomplete-multipart-uploads" &&
      aws_s3_bucket_lifecycle_configuration.this.rule[1].status == "Enabled" &&
      aws_s3_bucket_lifecycle_configuration.this.rule[1].abort_incomplete_multipart_upload[0].days_after_initiation == 7 &&
      aws_s3_bucket_lifecycle_configuration.this.rule[1].filter[0].prefix == ""
    )
    error_message = "rule 1 must abort incomplete multipart uploads after 7 days, for every key"
  }
}

run "lifecycle_custom" {
  command = plan

  variables {
    noncurrent_version_expiration_days = 90
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[0].noncurrent_version_expiration[0].noncurrent_days == 90
    error_message = "noncurrent expiry must come from the variable"
  }
}

run "tls_only_policy" {
  command = plan

  assert {
    condition = (
      length(jsondecode(aws_s3_bucket_policy.this.policy).Statement) == 1 &&
      jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Sid == "DenyInsecureTransport" &&
      jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Effect == "Deny" &&
      jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
    )
    error_message = "the bucket policy must be exactly the TLS-only deny"
  }
}

run "outputs" {
  command = plan

  assert {
    condition = (
      output.name == "jwall-engineering-rusty-chess-records" &&
      output.arn == "arn:aws:s3:::jwall-engineering-rusty-chess-records"
    )
    error_message = "outputs must describe the bucket"
  }
}

run "rejects_bad_name" {
  command = plan

  variables {
    name = "Bad_Name"
  }

  expect_failures = [var.name]
}

run "rejects_zero_days" {
  command = plan

  variables {
    noncurrent_version_expiration_days = 0
  }

  expect_failures = [var.noncurrent_version_expiration_days]
}
