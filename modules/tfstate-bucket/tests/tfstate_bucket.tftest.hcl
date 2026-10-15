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

# --- Hardened policy ----------------------------------------------------------

run "hardened_policy" {
  command = plan

  variables {
    admin_principal_arns = [
      "arn:aws:iam::123456789012:user/admin",
      "arn:aws:iam::123456789012:role/jwall-engineering-infra-ci-apply",
    ]
    prefix_access = {
      "project=infra/env=prod/infra-prod.tfstate" = {
        read  = ["arn:aws:iam::123456789012:role/jwall-engineering-infra-ci-plan"]
        write = ["arn:aws:iam::123456789012:role/jwall-engineering-infra-ci-apply"]
      }
      "project=guitar/" = {
        read  = ["arn:aws:iam::123456789012:role/jwall-engineering-guitar-ci-plan"]
        write = ["arn:aws:iam::123456789012:role/jwall-engineering-guitar-ci-apply"]
      }
    }
  }

  assert {
    condition = [for s in jsondecode(output.policy).Statement : s.Sid] == [
      "DenyInsecureTransport",
      "DenyUnlistedListing",
      "DenyObjectsOutsidePrefixes",
      "DenyOutsidePrefix0",
      "DenyOutsidePrefix1",
      "DenyStateWritesByReaders",
      "DenyUnmanagedConfiguration",
    ]
    error_message = "the hardened policy must contain exactly the documented statements, in order"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(output.policy).Statement : s.Effect == "Deny" && s.Principal == "*"
    ])
    error_message = "every statement must be a Deny for Principal = *; exemption must never grant access"
  }

  assert {
    condition = [for s in jsondecode(output.policy).Statement : s if s.Sid == "DenyUnlistedListing"][0].Condition.ArnNotEquals["aws:PrincipalArn"] == [
      "arn:aws:iam::123456789012:role/jwall-engineering-guitar-ci-plan",
      "arn:aws:iam::123456789012:role/jwall-engineering-infra-ci-plan",
      "arn:aws:iam::123456789012:role/jwall-engineering-guitar-ci-apply",
      "arn:aws:iam::123456789012:role/jwall-engineering-infra-ci-apply",
      "arn:aws:iam::123456789012:user/admin",
    ]
    error_message = "only listed principals and admins may list the bucket"
  }

  assert {
    condition = (
      [for s in jsondecode(output.policy).Statement : s if s.Sid == "DenyObjectsOutsidePrefixes"][0].NotResource == [
        "arn:aws:s3:::jwall-engineering-tfstate/project=guitar/*",
        "arn:aws:s3:::jwall-engineering-tfstate/project=infra/env=prod/infra-prod.tfstate*",
      ] &&
      jsonencode([for s in jsondecode(output.policy).Statement : s if s.Sid == "DenyObjectsOutsidePrefixes"][0].Condition.ArnNotEquals["aws:PrincipalArn"]) == jsonencode(var.admin_principal_arns)
    )
    error_message = "objects outside every declared prefix must be reachable by admins only"
  }

  assert {
    condition = (
      [for s in jsondecode(output.policy).Statement : s if s.Sid == "DenyOutsidePrefix0"][0].Resource == "arn:aws:s3:::jwall-engineering-tfstate/project=guitar/*" &&
      [for s in jsondecode(output.policy).Statement : s if s.Sid == "DenyOutsidePrefix0"][0].Condition.ArnNotEquals["aws:PrincipalArn"] == [
        "arn:aws:iam::123456789012:role/jwall-engineering-guitar-ci-plan",
        "arn:aws:iam::123456789012:role/jwall-engineering-guitar-ci-apply",
        "arn:aws:iam::123456789012:user/admin",
        "arn:aws:iam::123456789012:role/jwall-engineering-infra-ci-apply",
      ]
    )
    error_message = "a prefix must be reachable only by its own readers, writers and the admins"
  }

  assert {
    condition = (
      [for s in jsondecode(output.policy).Statement : s if s.Sid == "DenyStateWritesByReaders"][0].NotResource == [
        "arn:aws:s3:::jwall-engineering-tfstate/project=guitar/*.tflock",
        "arn:aws:s3:::jwall-engineering-tfstate/project=infra/env=prod/infra-prod.tfstate*.tflock",
      ] &&
      [for s in jsondecode(output.policy).Statement : s if s.Sid == "DenyStateWritesByReaders"][0].Condition.ArnEquals["aws:PrincipalArn"] == [
        "arn:aws:iam::123456789012:role/jwall-engineering-guitar-ci-plan",
        "arn:aws:iam::123456789012:role/jwall-engineering-infra-ci-plan",
      ]
    )
    error_message = "readers may write only .tflock objects"
  }

  assert {
    condition = (
      contains([for s in jsondecode(output.policy).Statement : s if s.Sid == "DenyUnmanagedConfiguration"][0].Action, "s3:PutBucket*") &&
      [for s in jsondecode(output.policy).Statement : s if s.Sid == "DenyUnmanagedConfiguration"][0].Resource == "arn:aws:s3:::jwall-engineering-tfstate" &&
      jsonencode([for s in jsondecode(output.policy).Statement : s if s.Sid == "DenyUnmanagedConfiguration"][0].Condition.ArnNotEquals["aws:PrincipalArn"]) == jsonencode(var.admin_principal_arns)
    )
    error_message = "only admins may change bucket configuration, including the bucket policy"
  }

  assert {
    condition     = length(output.policy) <= 20480
    error_message = "the policy must fit S3's 20 KB bucket policy limit"
  }
}

run "no_reader_statement_without_readers" {
  command = plan

  variables {
    admin_principal_arns = ["arn:aws:iam::123456789012:user/admin"]
    prefix_access = {
      "project=guitar/" = { write = ["arn:aws:iam::123456789012:role/jwall-engineering-guitar-ci-apply"] }
    }
  }

  assert {
    condition     = !contains([for s in jsondecode(output.policy).Statement : s.Sid], "DenyStateWritesByReaders")
    error_message = "DenyStateWritesByReaders must be omitted when no principal is read-only"
  }
}

run "rejects_prefix_access_without_admins" {
  command = plan

  variables {
    prefix_access = {
      "project=guitar/" = { read = ["arn:aws:iam::123456789012:role/jwall-engineering-guitar-ci-plan"] }
    }
  }

  expect_failures = [var.prefix_access]
}

run "rejects_overlapping_prefixes" {
  command = plan

  variables {
    admin_principal_arns = ["arn:aws:iam::123456789012:user/admin"]
    prefix_access = {
      "project=guitar/"          = { read = ["arn:aws:iam::123456789012:role/a"] }
      "project=guitar/env=prod/" = { read = ["arn:aws:iam::123456789012:role/b"] }
    }
  }

  expect_failures = [var.prefix_access]
}

run "rejects_wildcard_prefix" {
  command = plan

  variables {
    admin_principal_arns = ["arn:aws:iam::123456789012:user/admin"]
    prefix_access = {
      "project=*/" = { read = ["arn:aws:iam::123456789012:role/a"] }
    }
  }

  expect_failures = [var.prefix_access]
}

run "rejects_wildcard_principal" {
  command = plan

  variables {
    admin_principal_arns = ["arn:aws:iam::123456789012:role/jwall-engineering-*"]
  }

  expect_failures = [var.admin_principal_arns]
}

run "rejects_entry_without_principals" {
  command = plan

  variables {
    admin_principal_arns = ["arn:aws:iam::123456789012:user/admin"]
    prefix_access = {
      "project=guitar/" = {}
    }
  }

  expect_failures = [var.prefix_access]
}
