data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # Buckets the policy may fully manage. site-bucket names buckets
  # <name_root>-<project>, so the default pattern covers every project and
  # adding a project needs no IAM change. Bucket ARNs only: no statement
  # reaches objects, so the state bucket's objects stay out of reach even
  # though the default pattern matches it.
  managed_bucket_patterns = coalesce(var.managed_bucket_patterns, ["${var.name_root}-*"])
  managed_bucket_arns     = [for p in local.managed_bucket_patterns : "arn:aws:s3:::${p}"]

  managed_role_arn   = "arn:aws:iam::${local.account_id}:role/${var.name_root}-*"
  managed_policy_arn = "arn:aws:iam::${local.account_id}:policy/${var.name_root}-*"

  attachable_policy_arns = coalesce(var.attachable_policy_arns, [local.managed_policy_arn])

  # Write-only: pair with foundation/read for refresh, and with tfstate/write
  # for the stack's own state.
  policy = {
    Version = "2012-10-17"
    Statement = [
      # --- S3: state bucket configuration and project site buckets ------------
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
            "iam:PolicyARN" = local.attachable_policy_arns
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

      # --- ECR: only <name_root>-* repositories ---------------------------------
      # Repository management only. Pushing images is ecr/push, requested
      # separately for the one repository a role publishes to.
      {
        Sid    = "ManageOrganisationRepositories"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository",
          "ecr:DeleteRepository",
          "ecr:PutImageTagMutability",
          "ecr:PutImageScanningConfiguration",
          "ecr:PutEncryptionConfiguration",
          "ecr:PutLifecyclePolicy",
          "ecr:DeleteLifecyclePolicy",
          "ecr:SetRepositoryPolicy",
          "ecr:DeleteRepositoryPolicy",
          "ecr:TagResource",
          "ecr:UntagResource",
        ]
        Resource = "arn:aws:ecr:us-east-1:${local.account_id}:repository/${var.name_root}-*"
      },

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

resource "aws_iam_policy" "this" {
  name        = var.name
  description = "CI policy foundation/manage: manage the state bucket configuration, managed buckets, <name_root>-* IAM and ECR repositories, and the hosted zone"
  policy      = jsonencode(local.policy)

  tags = {
    Component = "ci"
  }
}
