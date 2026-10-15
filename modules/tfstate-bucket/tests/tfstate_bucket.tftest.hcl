mock_provider "aws" {
  override_during = plan

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::jwall-engineering-tfstate"
      id  = "jwall-engineering-tfstate"
    }
  }
}

variables {
  name = "jwall-engineering-tfstate"
}

run "bucket_and_tags" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "jwall-engineering-tfstate"
    error_message = "bucket name must be var.name"
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Name"] == "jwall-engineering-tfstate"
    error_message = "Name tag must equal the bucket name"
  }

  assert {
    condition     = aws_s3_bucket.this.tags == tomap({ Name = "jwall-engineering-tfstate", Component = "terraform-state" })
    error_message = "tags must be exactly Name and Component = terraform-state"
  }
}

run "versioning_enabled" {
  command = plan

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "versioning must be Enabled"
  }
}

run "sse_s3_with_bucket_key" {
  command = plan

  assert {
    condition = (
      one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256" &&
      one(aws_s3_bucket_server_side_encryption_configuration.this.rule).bucket_key_enabled == true
    )
    error_message = "encryption must be SSE-S3 (AES256) with bucket_key_enabled"
  }
}

run "public_access_fully_blocked" {
  command = plan

  assert {
    condition = (
      aws_s3_bucket_public_access_block.this.block_public_acls &&
      aws_s3_bucket_public_access_block.this.block_public_policy &&
      aws_s3_bucket_public_access_block.this.ignore_public_acls &&
      aws_s3_bucket_public_access_block.this.restrict_public_buckets
    )
    error_message = "all four Block Public Access flags must be true"
  }
}

run "bucket_owner_enforced" {
  command = plan

  assert {
    condition     = aws_s3_bucket_ownership_controls.this.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "object ownership must be BucketOwnerEnforced"
  }
}

run "policy_denies_insecure_transport" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.this.policy).Statement) == 1
    error_message = "bucket policy must have exactly one statement"
  }

  assert {
    condition = (
      jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Sid == "DenyInsecureTransport" &&
      jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Effect == "Deny" &&
      jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Principal == "*" &&
      jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Action == "s3:*" &&
      jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Resource == [
        "arn:aws:s3:::jwall-engineering-tfstate",
        "arn:aws:s3:::jwall-engineering-tfstate/*",
      ] &&
      jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
    )
    error_message = "bucket policy must deny s3:* on the bucket and its objects when aws:SecureTransport is false"
  }
}

run "outputs" {
  command = plan

  assert {
    condition     = output.name == "jwall-engineering-tfstate" && output.arn == "arn:aws:s3:::jwall-engineering-tfstate"
    error_message = "outputs name and arn must describe the bucket"
  }
}

run "rejects_invalid_bucket_name" {
  command = plan

  variables {
    name = "Not_A_Bucket"
  }

  expect_failures = [var.name]
}
