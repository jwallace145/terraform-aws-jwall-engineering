locals {
  # GitHub issues the `sub` claim in one of two shapes depending on the
  # repository's OIDC settings: the classic repo:<owner>/<name> and the
  # immutable repo:<owner>@<owner_id>/<name>@<repository_id>. Trust both when
  # the IDs are supplied so the role works whichever form the repo uses.
  github_owner = split("/", var.repository)[0]
  github_name  = split("/", var.repository)[1]

  subject_prefixes = concat(
    ["repo:${var.repository}"],
    var.owner_id == null ? [] : ["repo:${local.github_owner}@${var.owner_id}/${local.github_name}@${var.repository_id}"],
  )

  # Every prefix joined to every suffix, prefixes outermost, so the classic
  # subjects come first and the immutable ones follow in the same order.
  subjects = flatten([
    for p in local.subject_prefixes : [for s in var.subjects : "${p}:${s}"]
  ])

  tags = merge(
    var.name_tag == null ? {} : { Name = var.name_tag },
    { Component = var.component },
  )
}

resource "aws_iam_role" "this" {
  name                 = var.name
  description          = var.description
  max_session_duration = var.max_session_duration

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = var.trust_statement_sid
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = local.subjects
          }
        }
      },
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "this" {
  for_each = { for k, doc in var.inline_policies : k => jsonencode(doc) }

  name   = "${var.name}-${each.key}"
  role   = aws_iam_role.this.id
  policy = each.value
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

# Keyed by a caller-chosen name rather than the ARN, so the ARN of a policy
# created in the same run may be unknown until apply.
resource "aws_iam_role_policy_attachment" "keyed" {
  for_each = var.managed_policies

  role       = aws_iam_role.this.name
  policy_arn = each.value
}
