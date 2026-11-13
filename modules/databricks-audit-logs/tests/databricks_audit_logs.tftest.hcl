mock_provider "aws" {
  override_during = plan

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::jwall-engineering-databricks-audit-logs"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111122223333:role/jwall-engineering-databricks-log-delivery"
    }
  }
}

mock_provider "databricks" {
  override_during = plan
}

variables {
  account_id = "11111111-2222-3333-4444-555555555555"
}

run "log_delivery_is_audit_json_under_prefix" {
  command = plan

  assert {
    condition     = databricks_mws_log_delivery.audit.log_type == "AUDIT_LOGS" && databricks_mws_log_delivery.audit.output_format == "JSON"
    error_message = "log delivery must be AUDIT_LOGS in JSON"
  }

  assert {
    condition     = databricks_mws_log_delivery.audit.delivery_path_prefix == "audit" && databricks_mws_log_delivery.audit.account_id == var.account_id
    error_message = "log delivery must write under the audit prefix for the given account"
  }
}

run "audit_role_trust_requires_external_id" {
  command = plan

  assert {
    condition = (
      length(jsondecode(aws_iam_role.log_delivery.assume_role_policy).Statement) == 1 &&
      jsondecode(aws_iam_role.log_delivery.assume_role_policy).Statement[0].Effect == "Allow" &&
      jsondecode(aws_iam_role.log_delivery.assume_role_policy).Statement[0].Action == "sts:AssumeRole" &&
      jsondecode(aws_iam_role.log_delivery.assume_role_policy).Statement[0].Principal.AWS == "arn:aws:iam::414351767826:role/SaasUsageDeliveryRole-prod-IAMRole-3PLHICCRR1TK" &&
      jsondecode(aws_iam_role.log_delivery.assume_role_policy).Statement[0].Condition.StringEquals["sts:ExternalId"] == var.account_id
    )
    error_message = "trust must allow only the Databricks SaasUsageDeliveryRole (not the account root), with sts:ExternalId = account_id under StringEquals"
  }

  assert {
    condition     = databricks_mws_credentials.log_delivery.role_arn == "arn:aws:iam::111122223333:role/jwall-engineering-databricks-log-delivery"
    error_message = "Databricks credentials must point at the log delivery role"
  }
}

run "audit_bucket_blocks_public_access" {
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
    condition = (
      aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled" &&
      tolist(aws_s3_bucket_server_side_encryption_configuration.this.rule)[0].apply_server_side_encryption_by_default[0].sse_algorithm == "AES256" &&
      tolist(aws_s3_bucket_ownership_controls.this.rule)[0].object_ownership == "BucketOwnerEnforced"
    )
    error_message = "bucket must be versioned, SSE-S3 encrypted and ownership-enforced"
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == null || aws_s3_bucket.this.force_destroy == false
    error_message = "audit logs must never be force-destroyable"
  }
}

run "audit_bucket_policy_scoped_to_prefix" {
  command = plan

  # Databricks' own statements: Allow statements for the log delivery role.
  # Object resources must sit under <prefix>/; bucket-ARN statements must be
  # GetBucketLocation or carry an s3:prefix condition limited to the prefix.
  assert {
    condition = alltrue([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement :
      alltrue([
        for r in flatten([s.Resource]) :
        (endswith(r, "/audit/*") || endswith(r, "/audit/")) ||
        (r == aws_s3_bucket.this.arn && (
          s.Action == "s3:GetBucketLocation" ||
          (can(s.Condition.StringLike["s3:prefix"]) && toset(s.Condition.StringLike["s3:prefix"]) == toset(["audit", "audit/*"]))
        ))
      ])
      if s.Effect == "Allow"
    ])
    error_message = "every Allow must target <bucket>/audit/ or audit/*, or the bucket ARN for GetBucketLocation or with an s3:prefix condition limited to audit"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement :
      s.Effect == "Allow" && contains(flatten([s.Action]), "s3:ListBucket") && contains(flatten([s.Action]), "s3:ListBucketMultipartUploads")
    ])
    error_message = "the documented prefix-conditioned ListBucket / ListBucketMultipartUploads statement must be present"
  }

  assert {
    condition = length([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s
      if s.Effect == "Allow" && s.Principal.AWS == "arn:aws:iam::111122223333:role/jwall-engineering-databricks-log-delivery"
    ]) == 3
    error_message = "the log delivery role must get exactly the bucket-location, object and prefix-listing statements"
  }

  # The events/ prefix belongs to the account's own principals: nothing may deny it
  # other than non-TLS requests.
  assert {
    condition = alltrue([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement :
      s.Condition.Bool["aws:SecureTransport"] == "false"
      if s.Effect == "Deny"
    ]) && length([for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Effect == "Deny"]) == 1
    error_message = "the only Deny must be the non-TLS one, so other prefixes stay usable by the account's principals"
  }

  assert {
    condition = alltrue([
      for a in flatten([for s in jsondecode(aws_iam_role_policy.log_delivery.policy).Statement : s.Action]) :
      !contains(["s3:*", "s3:DeleteBucket", "s3:PutBucketPolicy"], a)
    ])
    error_message = "the role policy must not carry bucket administration rights"
  }
}

run "prefix_follows_variable" {
  command = plan

  variables {
    prefix = "logs"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement :
      alltrue([
        for r in flatten([s.Resource]) :
        (endswith(r, "/logs/*") || endswith(r, "/logs/")) ||
        (r == aws_s3_bucket.this.arn && (
          s.Action == "s3:GetBucketLocation" ||
          (can(s.Condition.StringLike["s3:prefix"]) && toset(s.Condition.StringLike["s3:prefix"]) == toset(["logs", "logs/*"]))
        ))
      ])
      if s.Effect == "Allow"
    ]) && databricks_mws_log_delivery.audit.delivery_path_prefix == "logs"
    error_message = "a custom prefix must flow into the policy and the delivery path"
  }
}

run "rejects_bad_account_id" {
  command = plan

  variables {
    account_id = "not-a-uuid"
  }

  expect_failures = [var.account_id]
}

run "rejects_prefix_with_slash" {
  command = plan

  variables {
    prefix = "audit/"
  }

  expect_failures = [var.prefix]
}
