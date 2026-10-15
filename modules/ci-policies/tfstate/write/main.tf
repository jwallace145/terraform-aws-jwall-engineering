locals {
  # With `key`, the policy covers one stack's state object and its lock. With
  # `prefix`, it covers every object under the prefix.
  by_key = var.key != null
  # The variables guarantee exactly one is set; try() only keeps static
  # analysis (tflint), which leaves both null, from failing.
  target      = try(coalesce(var.key, var.prefix), "")
  list_prefix = "${local.target}*"
  state_arn   = local.by_key ? "${var.bucket_arn}/${local.target}" : "${var.bucket_arn}/${local.target}*"
  lock_arn    = local.by_key ? "${var.bucket_arn}/${local.target}.tflock" : "${var.bucket_arn}/${local.target}*.tflock"

  # Read and write the state, and take and release its lock. State objects are
  # never deleted; only the lock is.
  policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListState"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = var.bucket_arn
        Condition = {
          StringLike = {
            "s3:prefix" = local.list_prefix
          }
        }
      },
      {
        Sid      = "ReadWriteState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
        Resource = local.state_arn
      },
      {
        Sid      = "LockState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = local.lock_arn
      },
    ]
  }
}

resource "aws_iam_policy" "this" {
  name        = var.name
  description = "CI policy tfstate/write: read and write Terraform state and its lock"
  policy      = jsonencode(local.policy)

  tags = {
    Component = "ci"
  }
}
