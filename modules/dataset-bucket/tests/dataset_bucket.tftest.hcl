mock_provider "aws" {
  override_during = plan

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::jwall-engineering-rusty-chess-nnue"
    }
  }
}

variables {
  name              = "jwall-engineering-rusty-chess-nnue"
  prefix            = "data/"
  writer_role_names = ["jwall-engineering-rusty-chess-task"]
}

run "bucket_hardening" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "jwall-engineering-rusty-chess-nnue"
    error_message = "bucket name must be var.name"
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
    condition     = aws_s3_bucket.this.tags == tomap({ Name = "jwall-engineering-rusty-chess-nnue", Component = "dataset", Purpose = "dataset" })
    error_message = "the bucket must carry Name, Component = dataset and Purpose = dataset"
  }
}

run "kept_forever_in_intelligent_tiering" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule) == 2
    error_message = "two rules: the tiering transition and the multipart cleanup"
  }

  assert {
    condition = (
      aws_s3_bucket_lifecycle_configuration.this.rule[0].id == "intelligent-tiering" &&
      aws_s3_bucket_lifecycle_configuration.this.rule[0].status == "Enabled" &&
      aws_s3_bucket_lifecycle_configuration.this.rule[0].filter[0].prefix == "" &&
      tolist(aws_s3_bucket_lifecycle_configuration.this.rule[0].transition)[0].days == 0 &&
      tolist(aws_s3_bucket_lifecycle_configuration.this.rule[0].transition)[0].storage_class == "INTELLIGENT_TIERING"
    )
    error_message = "rule 0 must move every object to Intelligent-Tiering at once by default"
  }

  assert {
    condition = (
      aws_s3_bucket_lifecycle_configuration.this.rule[1].id == "abort-incomplete-multipart-uploads" &&
      aws_s3_bucket_lifecycle_configuration.this.rule[1].abort_incomplete_multipart_upload[0].days_after_initiation == 7
    )
    error_message = "rule 1 must abort incomplete multipart uploads after 7 days"
  }

  assert {
    condition = alltrue([
      for r in aws_s3_bucket_lifecycle_configuration.this.rule :
      length(r.expiration) == 0 && length(r.noncurrent_version_expiration) == 0
    ])
    error_message = "no rule may expire data: the dataset is kept"
  }
}

run "transition_days" {
  command = plan

  variables {
    transition_days = 30
  }

  assert {
    condition     = tolist(aws_s3_bucket_lifecycle_configuration.this.rule[0].transition)[0].days == 30
    error_message = "the transition must follow transition_days"
  }
}

run "denies_insecure_transport" {
  command = plan

  assert {
    condition = (
      [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "DenyInsecureTransport"][0].Effect == "Deny" &&
      [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "DenyInsecureTransport"][0].Action == "s3:*" &&
      [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "DenyInsecureTransport"][0].Condition.Bool["aws:SecureTransport"] == "false"
    )
    error_message = "the bucket policy must deny every request without TLS"
  }

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.this.policy).Statement) == 1
    error_message = "without readers the policy grants nothing"
  }
}

run "writers_add_only_under_the_prefix" {
  command = plan

  assert {
    condition     = aws_iam_role_policy.writer["jwall-engineering-rusty-chess-task"].role == "jwall-engineering-rusty-chess-task"
    error_message = "each writer role gets the write policy"
  }

  assert {
    condition = (
      jsonencode(sort(flatten([[for s in jsondecode(aws_iam_role_policy.writer["jwall-engineering-rusty-chess-task"].policy).Statement : s.Action if s.Sid == "AddDatasetObjects"][0]]))) == jsonencode(["s3:AbortMultipartUpload", "s3:PutObject"]) &&
      [for s in jsondecode(aws_iam_role_policy.writer["jwall-engineering-rusty-chess-task"].policy).Statement : s.Resource if s.Sid == "AddDatasetObjects"][0] == "arn:aws:s3:::jwall-engineering-rusty-chess-nnue/data/*"
    )
    error_message = "writers may put objects (and abort their own uploads) under the prefix only"
  }

  assert {
    condition = (
      [for s in jsondecode(aws_iam_role_policy.writer["jwall-engineering-rusty-chess-task"].policy).Statement : s.Action if s.Sid == "ListDatasetPrefix"][0] == "s3:ListBucket" &&
      [for s in jsondecode(aws_iam_role_policy.writer["jwall-engineering-rusty-chess-task"].policy).Statement : s.Resource if s.Sid == "ListDatasetPrefix"][0] == "arn:aws:s3:::jwall-engineering-rusty-chess-nnue" &&
      [for s in jsondecode(aws_iam_role_policy.writer["jwall-engineering-rusty-chess-task"].policy).Statement : s.Condition if s.Sid == "ListDatasetPrefix"][0].StringLike["s3:prefix"] == "data/*"
    )
    error_message = "writers may list under the prefix only"
  }

  assert {
    condition = !anytrue([
      for a in flatten([for s in jsondecode(aws_iam_role_policy.writer["jwall-engineering-rusty-chess-task"].policy).Statement : tolist(flatten([s.Action]))]) :
      can(regex("^s3:(Get|Delete|PutBucket|PutObjectAcl|\\*)", a))
    ])
    error_message = "writers never read, delete or reconfigure: the dataset is append-only"
  }

  assert {
    condition     = length(jsondecode(aws_iam_role_policy.writer["jwall-engineering-rusty-chess-task"].policy).Statement) == 2
    error_message = "the write policy has exactly the two statements"
  }
}

run "no_writers" {
  command = plan

  variables {
    writer_role_names = []
  }

  assert {
    condition     = length(aws_iam_role_policy.writer) == 0
    error_message = "no writers, no write policies"
  }
}

run "readers_read_the_prefix" {
  command = plan

  variables {
    reader_role_arns = ["arn:aws:iam::123456789012:role/jwall-engineering-rusty-chess-train"]
  }

  assert {
    condition = (
      [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "ReadDatasetObjects"][0].Effect == "Allow" &&
      [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "ReadDatasetObjects"][0].Principal.AWS == ["arn:aws:iam::123456789012:role/jwall-engineering-rusty-chess-train"] &&
      [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "ReadDatasetObjects"][0].Action == "s3:GetObject" &&
      [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "ReadDatasetObjects"][0].Resource == "arn:aws:s3:::jwall-engineering-rusty-chess-nnue/data/*"
    )
    error_message = "readers may get objects under the prefix"
  }

  assert {
    condition = (
      [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "ListDatasetForReaders"][0].Action == "s3:ListBucket" &&
      [for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Sid == "ListDatasetForReaders"][0].Condition.StringLike["s3:prefix"] == "data/*"
    )
    error_message = "readers may list under the prefix"
  }
}

run "rejects_prefix_without_trailing_slash" {
  command = plan

  variables {
    prefix = "data"
  }

  expect_failures = [var.prefix]
}

run "rejects_empty_prefix" {
  command = plan

  variables {
    prefix = ""
  }

  expect_failures = [var.prefix]
}

run "rejects_leading_slash" {
  command = plan

  variables {
    prefix = "/data/"
  }

  expect_failures = [var.prefix]
}

run "rejects_negative_transition_days" {
  command = plan

  variables {
    transition_days = -1
  }

  expect_failures = [var.transition_days]
}

run "rejects_reader_that_is_not_a_role_arn" {
  command = plan

  variables {
    reader_role_arns = ["*"]
  }

  expect_failures = [var.reader_role_arns]
}
