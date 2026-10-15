data "aws_caller_identity" "current" {}

locals {
  component   = "ci"
  account_id  = data.aws_caller_identity.current.account_id
  name_prefix = "${var.name_root}-${var.project}"

  role_names = {
    plan  = "${local.name_prefix}-ci-plan"
    apply = "${local.name_prefix}-ci-apply"
  }

  descriptions = {
    plan  = "terraform plan for ${var.repository} pull requests (read-only)"
    apply = "terraform apply for ${var.repository} releases (${var.apply_environment} environment)"
  }

  # GitHubProdEnvironment for `prod`, GitHubStagingEuEnvironment for `staging-eu`.
  apply_trust_sid = "GitHub${join("", [for w in split(" ", replace(replace(var.apply_environment, "-", " "), "_", " ")) : title(w)])}Environment"

  read_only_access_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"

  # Buckets the apply role may fully manage. site-bucket names buckets
  # <name_root>-<project>, so the default pattern covers every project and
  # adding a project needs no IAM change.
  managed_bucket_patterns = coalesce(var.managed_bucket_patterns, ["${var.name_root}-*"])

  managed_bucket_arns = flatten([
    for pattern in local.managed_bucket_patterns : [
      "arn:aws:s3:::${pattern}",
      "arn:aws:s3:::${pattern}/*",
    ]
  ])

  managed_role_arn   = "arn:aws:iam::${local.account_id}:role/${var.name_root}-*"
  managed_policy_arn = "arn:aws:iam::${local.account_id}:policy/${var.name_root}-*"

  # Managed policies the apply role may attach to the roles it creates.
  attachable_policy_arns = coalesce(var.attachable_policy_arns, [
    local.read_only_access_arn,
    local.managed_policy_arn,
  ])

  state_object_arn = "${var.state_bucket_arn}/${var.state_key}"
  state_lock_arn   = "${var.state_bucket_arn}/${var.state_key}.tflock"

  # aws_iam_policy_document renders a one-element list as a bare string. The
  # source roles were built with it, so render the same way here.
  attachable_policy_arns_value = jsondecode(
    length(local.attachable_policy_arns) == 1 ? jsonencode(local.attachable_policy_arns[0]) : jsonencode(local.attachable_policy_arns)
  )

  list_own_state_prefix = {
    Sid      = "ListOwnStatePrefix"
    Effect   = "Allow"
    Action   = "s3:ListBucket"
    Resource = var.state_bucket_arn
    Condition = {
      StringLike = {
        "s3:prefix" = "${var.state_key}*"
      }
    }
  }

  # Plan role: read everything (ReadOnlyAccess), read own state, lock own state.
  plan_state_policy = {
    Version = "2012-10-17"
    Statement = [
      local.list_own_state_prefix,
      {
        Sid      = "ReadOwnState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = [local.state_object_arn, local.state_lock_arn]
      },
      {
        Sid      = "LockOwnState"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = local.state_lock_arn
      },
    ]
  }

  # Apply role: manage everything in the foundation stack.
  apply_manage_policy = {
    Version = "2012-10-17"
    Statement = [
      # --- Terraform state ----------------------------------------------------
      local.list_own_state_prefix,
      {
        Sid      = "ReadWriteOwnState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
        Resource = local.state_object_arn
      },
      {
        Sid      = "LockOwnState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = local.state_lock_arn
      },

      # --- S3: state bucket configuration and project site buckets ------------
      # Bucket-level configuration only on the state bucket (no DeleteBucket,
      # no object access beyond this stack's own state above).
      {
        Sid    = "ManageStateBucketConfiguration"
        Effect = "Allow"
        Action = [
          "s3:GetBucket*",
          "s3:GetEncryptionConfiguration",
          "s3:GetLifecycleConfiguration",
          "s3:PutBucketVersioning",
          "s3:PutEncryptionConfiguration",
          "s3:PutBucketPublicAccessBlock",
          "s3:PutBucketOwnershipControls",
          "s3:PutBucketPolicy",
          "s3:PutBucketTagging",
          "s3:PutLifecycleConfiguration",
        ]
        Resource = var.state_bucket_arn
      },
      {
        Sid      = "ManageSiteBuckets"
        Effect   = "Allow"
        Action   = "s3:*"
        Resource = local.managed_bucket_arns
      },
      {
        Sid      = "DenyStateBucketDeletion"
        Effect   = "Deny"
        Action   = ["s3:DeleteBucket", "s3:DeleteBucketPolicy"]
        Resource = var.state_bucket_arn
      },

      # --- IAM: only <name_root>-* roles and policies ---------------------------
      {
        Sid    = "ManageOrganisationRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:UpdateRole",
          "iam:UpdateRoleDescription",
          "iam:UpdateAssumeRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:ListRoleTags",
          "iam:PutRolePolicy",
          "iam:GetRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:DetachRolePolicy",
        ]
        Resource = local.managed_role_arn
      },
      # Attaching a managed policy is where privilege escalation would happen,
      # so the attachable policies are allow-listed.
      {
        Sid      = "AttachAllowListedPolicies"
        Effect   = "Allow"
        Action   = "iam:AttachRolePolicy"
        Resource = local.managed_role_arn
        Condition = {
          ArnLike = {
            "iam:PolicyARN" = local.attachable_policy_arns_value
          }
        }
      },
      {
        Sid    = "ManageOrganisationPolicies"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:SetDefaultPolicyVersion",
          "iam:TagPolicy",
          "iam:UntagPolicy",
          "iam:ListPolicyTags",
          "iam:ListEntitiesForPolicy",
        ]
        Resource = local.managed_policy_arn
      },

      # The GitHub OIDC provider is not owned by the caller, so this role only
      # reads it (covered by ReadOnlyAccess).

      # --- Route 53: the caller's zone only -------------------------------------
      {
        Sid    = "ManageHostedZone"
        Effect = "Allow"
        Action = [
          "route53:GetHostedZone",
          "route53:UpdateHostedZoneComment",
          "route53:ListResourceRecordSets",
          "route53:ChangeResourceRecordSets",
          "route53:ChangeTagsForResource",
          "route53:ListTagsForResource",
          "route53:GetDNSSEC",
        ]
        Resource = var.hosted_zone_arn
      },
      {
        Sid      = "ReadRoute53Changes"
        Effect   = "Allow"
        Action   = "route53:GetChange"
        Resource = "arn:aws:route53:::change/*"
      },
    ]
  }
}

module "plan" {
  source = "../github-oidc-role"

  name                = local.role_names.plan
  description         = local.descriptions.plan
  repository          = var.repository
  owner_id            = var.owner_id
  repository_id       = var.repository_id
  oidc_provider_arn   = var.oidc_provider_arn
  subjects            = ["pull_request"]
  trust_statement_sid = "GitHubPullRequests"
  component           = local.component
  name_tag            = local.role_names.plan

  managed_policy_arns = [local.read_only_access_arn]

  inline_policies = {
    state = local.plan_state_policy
  }
}

module "apply" {
  source = "../github-oidc-role"

  name                = local.role_names.apply
  description         = local.descriptions.apply
  repository          = var.repository
  owner_id            = var.owner_id
  repository_id       = var.repository_id
  oidc_provider_arn   = var.oidc_provider_arn
  subjects            = ["environment:${var.apply_environment}"]
  trust_statement_sid = local.apply_trust_sid
  component           = local.component
  name_tag            = local.role_names.apply

  # Refresh and drift detection read resources Terraform does not otherwise
  # touch; ReadOnlyAccess covers that without listing every Get*/List* action.
  managed_policy_arns = [local.read_only_access_arn]

  inline_policies = {
    manage = local.apply_manage_policy
  }
}
