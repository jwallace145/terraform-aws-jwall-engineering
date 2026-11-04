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

run "role_grants_read_and_write_sub_prefixes" {
  command = plan

  variables {
    role_grants = {
      "jwall-engineering-rusty-chess-task-gpu" = { read = ["selfplay/"], write = ["nets/"] }
    }
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.grant["jwall-engineering-rusty-chess-task-gpu"].policy).Statement == [
      {
        Sid      = "ReadDatasetObjects"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = ["arn:aws:s3:::jwall-engineering-rusty-chess-nnue/data/selfplay/*"]
      },
      {
        Sid      = "AddDatasetObjects"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:AbortMultipartUpload"]
        Resource = ["arn:aws:s3:::jwall-engineering-rusty-chess-nnue/data/nets/*"]
      },
      {
        Sid       = "ListDatasetPrefixes"
        Effect    = "Allow"
        Action    = "s3:ListBucket"
        Resource  = "arn:aws:s3:::jwall-engineering-rusty-chess-nnue"
        Condition = { StringLike = { "s3:prefix" = ["data/selfplay/*", "data/nets/*"] } }
      },
    ]
    error_message = "a grant reads only its read sub-prefixes, adds only under its write sub-prefixes and lists only those"
  }

  assert {
    condition = !anytrue([
      for s in jsondecode(aws_iam_role_policy.grant["jwall-engineering-rusty-chess-task-gpu"].policy).Statement :
      anytrue([for a in flatten([s.Action]) : startswith(a, "s3:Delete") || a == "s3:*"])
    ])
    error_message = "a grant never deletes"
  }

  assert {
    condition     = aws_iam_role_policy.grant["jwall-engineering-rusty-chess-task-gpu"].role == "jwall-engineering-rusty-chess-task-gpu"
    error_message = "the grant is an inline policy on the named role"
  }
}

run "role_grant_read_only" {
  command = plan

  variables {
    role_grants = { "some-reader" = { read = ["selfplay/"] } }
  }

  assert {
    condition     = [for s in jsondecode(aws_iam_role_policy.grant["some-reader"].policy).Statement : s.Sid] == ["ReadDatasetObjects", "ListDatasetPrefixes"]
    error_message = "a read-only grant has no write statement"
  }
}

run "rejects_empty_role_grant" {
  command = plan

  variables {
    role_grants = { "some-role" = {} }
  }

  expect_failures = [var.role_grants]
}

run "rejects_role_grant_with_leading_slash" {
  command = plan

  variables {
    role_grants = { "some-role" = { read = ["/selfplay/"] } }
  }

  expect_failures = [var.role_grants]
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

run "defaults_are_unchanged" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_versioning.this) == 0
    error_message = "versioning must be off by default"
  }

  assert {
    condition     = toset([for r in aws_s3_bucket_lifecycle_configuration.this.rule : r.id]) == toset(["intelligent-tiering", "abort-incomplete-multipart-uploads"]) && length(aws_s3_bucket_lifecycle_configuration.this.rule) == 2
    error_message = "by default the lifecycle has exactly the tiering and multipart rules"
  }
}

run "versioning_on" {
  command = plan

  variables {
    versioning = true
  }

  assert {
    condition     = aws_s3_bucket_versioning.this[0].versioning_configuration[0].status == "Enabled"
    error_message = "versioning must be Enabled when requested"
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule) == 2
    error_message = "versioning alone must not add expiry rules"
  }
}

run "expiry_only_where_named" {
  command = plan

  variables {
    expire_prefixes = { "tmp/" = 30 }
  }

  assert {
    condition     = length([for r in aws_s3_bucket_lifecycle_configuration.this.rule : r if length(r.expiration) > 0]) == 1
    error_message = "exactly one rule may expire objects"
  }

  assert {
    condition = alltrue([
      for r in aws_s3_bucket_lifecycle_configuration.this.rule :
      r.filter[0].prefix == "data/tmp/" && tolist(r.expiration)[0].days == 30
      if length(r.expiration) > 0
    ])
    error_message = "the expiring rule must be scoped to data/tmp/ and expire after 30 days"
  }

  assert {
    condition     = length([for r in aws_s3_bucket_lifecycle_configuration.this.rule : r if r.id == "expire-tmp-"]) == 1
    error_message = "the rule id must be expire-<prefix with / replaced by ->"
  }
}

run "noncurrent_expiry" {
  command = plan

  variables {
    versioning             = true
    expire_noncurrent_days = 90
  }

  assert {
    condition     = length([for r in aws_s3_bucket_lifecycle_configuration.this.rule : r if length(r.noncurrent_version_expiration) > 0]) == 1
    error_message = "exactly one rule may expire noncurrent versions"
  }

  assert {
    condition = alltrue([
      for r in aws_s3_bucket_lifecycle_configuration.this.rule :
      r.id == "expire-noncurrent-versions" && tolist(r.noncurrent_version_expiration)[0].noncurrent_days == 90 && r.filter[0].prefix == ""
      if length(r.noncurrent_version_expiration) > 0
    ])
    error_message = "noncurrent versions must expire after 90 days across the bucket"
  }
}

run "rejects_noncurrent_expiry_without_versioning" {
  command = plan

  variables {
    expire_noncurrent_days = 90
  }

  expect_failures = [var.expire_noncurrent_days]
}

run "rejects_expire_prefix_with_leading_slash" {
  command = plan

  variables {
    expire_prefixes = { "/tmp" = 30 }
  }

  expect_failures = [var.expire_prefixes]
}

run "rejects_zero_expiry_days" {
  command = plan

  variables {
    expire_prefixes = { "tmp/" = 0 }
  }

  expect_failures = [var.expire_prefixes]
}

run "rejects_zero_noncurrent_days" {
  command = plan

  variables {
    versioning             = true
    expire_noncurrent_days = 0
  }

  expect_failures = [var.expire_noncurrent_days]
}

run "write_once_statements" {
  command = plan

  variables {
    role_grants = { "some-role" = { write_once = ["runs/"] } }
  }

  assert {
    condition = [for s in jsondecode(aws_iam_role_policy.grant["some-role"].policy).Statement : s.Sid] == [
      "ListDatasetPrefixes", "AddDatasetObjectsIfAbsent", "AddDatasetObjectParts", "AbortDatasetUploads",
    ]
    error_message = "a write_once grant adds the three conditional-write statements after the list statement"
  }

  assert {
    condition = one([
      for s in jsondecode(aws_iam_role_policy.grant["some-role"].policy).Statement : s if s.Sid == "AddDatasetObjectsIfAbsent"
      ]) == {
      Sid       = "AddDatasetObjectsIfAbsent"
      Effect    = "Allow"
      Action    = "s3:PutObject"
      Resource  = ["arn:aws:s3:::jwall-engineering-rusty-chess-nnue/data/runs/*"]
      Condition = { StringEquals = { "s3:if-none-match" = "*" } }
    }
    error_message = "creating a new object requires If-None-Match: * (StringEquals on s3:if-none-match)"
  }

  assert {
    condition = one([
      for s in jsondecode(aws_iam_role_policy.grant["some-role"].policy).Statement : s if s.Sid == "AddDatasetObjectParts"
      ]) == {
      Sid       = "AddDatasetObjectParts"
      Effect    = "Allow"
      Action    = "s3:PutObject"
      Resource  = ["arn:aws:s3:::jwall-engineering-rusty-chess-nnue/data/runs/*"]
      Condition = { Bool = { "s3:ObjectCreationOperation" = "false" } }
    }
    error_message = "multipart parts are allowed only where the request does not itself create the object"
  }

  assert {
    condition = one([
      for s in jsondecode(aws_iam_role_policy.grant["some-role"].policy).Statement : s if s.Sid == "AbortDatasetUploads"
      ]) == {
      Sid      = "AbortDatasetUploads"
      Effect   = "Allow"
      Action   = "s3:AbortMultipartUpload"
      Resource = ["arn:aws:s3:::jwall-engineering-rusty-chess-nnue/data/runs/*"]
    }
    error_message = "abort is granted alone, on the write-once prefix only"
  }
}

run "write_once_has_no_unconditional_put" {
  command = plan

  variables {
    role_grants = {
      "some-role" = { read = ["selfplay/"], write = ["nets/"], write_once = ["runs/"] }
    }
  }

  assert {
    condition = !anytrue([
      for s in jsondecode(aws_iam_role_policy.grant["some-role"].policy).Statement :
      contains(flatten([s.Action]), "s3:PutObject")
      && !can(s.Condition)
      && anytrue([for r in flatten([s.Resource]) : endswith(r, "/data/runs/*")])
    ])
    error_message = "no statement may allow s3:PutObject on a write-once prefix without a Condition"
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_iam_role_policy.grant["some-role"].policy).Statement :
      s.Sid == "AddDatasetObjects" && !anytrue([for r in flatten([s.Resource]) : endswith(r, "/data/runs/*")])
    ])
    error_message = "the plain write statement still covers its own prefixes, never the write-once one"
  }
}

run "list_covers_write_once" {
  command = plan

  variables {
    role_grants = { "some-role" = { read = ["selfplay/"], write_once = ["runs/"] } }
  }

  assert {
    condition = one([
      for s in jsondecode(aws_iam_role_policy.grant["some-role"].policy).Statement : s if s.Sid == "ListDatasetPrefixes"
    ]).Condition.StringLike["s3:prefix"] == ["data/selfplay/*", "data/runs/*"]
    error_message = "a grant can list its write-once prefixes"
  }
}

run "plain_grants_unchanged" {
  command = plan

  variables {
    role_grants = { "some-role" = { read = ["selfplay/"], write = ["nets/"] } }
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.grant["some-role"].policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "ReadDatasetObjects"
          Effect   = "Allow"
          Action   = "s3:GetObject"
          Resource = ["arn:aws:s3:::jwall-engineering-rusty-chess-nnue/data/selfplay/*"]
        },
        {
          Sid      = "AddDatasetObjects"
          Effect   = "Allow"
          Action   = ["s3:PutObject", "s3:AbortMultipartUpload"]
          Resource = ["arn:aws:s3:::jwall-engineering-rusty-chess-nnue/data/nets/*"]
        },
        {
          Sid       = "ListDatasetPrefixes"
          Effect    = "Allow"
          Action    = "s3:ListBucket"
          Resource  = "arn:aws:s3:::jwall-engineering-rusty-chess-nnue"
          Condition = { StringLike = { "s3:prefix" = ["data/selfplay/*", "data/nets/*"] } }
        },
      ]
    }
    error_message = "a grant without write_once renders exactly today's three statements"
  }
}

run "never_delete" {
  command = plan

  variables {
    role_grants = {
      "a" = { read = ["selfplay/"], write = ["nets/"], write_once = ["runs/"] }
      "b" = { write_once = ["runs/"] }
    }
  }

  assert {
    condition = !anytrue(flatten([
      for r in ["a", "b"] : [
        for s in jsondecode(aws_iam_role_policy.grant[r].policy).Statement :
        anytrue([for a in flatten([s.Action]) : startswith(a, "s3:Delete") || a == "s3:*"])
      ]
    ]))
    error_message = "no grant, write-once or not, ever deletes"
  }
}

run "rejects_write_once_overlapping_write" {
  command = plan

  variables {
    role_grants = { "some-role" = { write = ["runs/"], write_once = ["runs/2026/"] } }
  }

  expect_failures = [var.role_grants]
}

run "rejects_write_once_overlapping_write_reversed" {
  command = plan

  variables {
    role_grants = { "some-role" = { write = ["runs/2026/"], write_once = ["runs/"] } }
  }

  expect_failures = [var.role_grants]
}

run "rejects_write_once_with_leading_slash" {
  command = plan

  variables {
    role_grants = { "some-role" = { write_once = ["/runs/"] } }
  }

  expect_failures = [var.role_grants]
}
