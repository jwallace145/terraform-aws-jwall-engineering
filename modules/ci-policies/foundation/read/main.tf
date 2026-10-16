data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  managed_bucket_patterns = coalesce(var.managed_bucket_patterns, ["${var.name_root}-*"])

  # Bucket ARNs only: none of these grant access to objects, so the state
  # bucket's objects stay out of reach even when a pattern matches it.
  bucket_arns = distinct(concat(
    [var.state_bucket_arn],
    [for p in local.managed_bucket_patterns : "arn:aws:s3:::${p}"],
  ))

  # Replaces ReadOnlyAccess. That AWS-managed policy grants s3:GetObject on
  # every bucket, which includes every project's Terraform state.
  policy = {
    Version = "2012-10-17"
    Statement = [
      {
        # s3:ListBucket is also what HeadBucket requires. It lists keys in the
        # state bucket, but cannot read them.
        Sid    = "ReadManagedBuckets"
        Effect = "Allow"
        Action = [
          "s3:GetBucket*",
          "s3:GetAccelerateConfiguration",
          "s3:GetEncryptionConfiguration",
          "s3:GetLifecycleConfiguration",
          "s3:GetReplicationConfiguration",
          "s3:GetIntelligentTieringConfiguration",
          "s3:ListBucket",
        ]
        Resource = local.bucket_arns
      },
      {
        Sid    = "ReadOrganisationRoles"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListRoleTags",
          "iam:ListInstanceProfilesForRole",
        ]
        Resource = "arn:aws:iam::${local.account_id}:role/${var.name_root}-*"
      },
      {
        Sid    = "ReadOrganisationPolicies"
        Effect = "Allow"
        Action = [
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:ListPolicyTags",
          "iam:ListEntitiesForPolicy",
        ]
        Resource = "arn:aws:iam::${local.account_id}:policy/${var.name_root}-*"
      },
      {
        Sid    = "ReadGitHubOidcProvider"
        Effect = "Allow"
        Action = [
          "iam:GetOpenIDConnectProvider",
          "iam:ListOpenIDConnectProviderTags",
        ]
        Resource = var.oidc_provider_arn
      },
      {
        # Looking the provider up by URL lists them first; the action has no
        # resource-level support.
        Sid      = "ListOidcProviders"
        Effect   = "Allow"
        Action   = "iam:ListOpenIDConnectProviders"
        Resource = "*"
      },
      {
        Sid    = "ReadOrganisationRepositories"
        Effect = "Allow"
        Action = [
          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
          "ecr:DescribeImageScanFindings",
          "ecr:ListImages",
          "ecr:ListTagsForResource",
          "ecr:GetLifecyclePolicy",
          "ecr:GetRepositoryPolicy",
        ]
        Resource = "arn:aws:ecr:us-east-1:${local.account_id}:repository/${var.name_root}-*"
      },
      {
        Sid    = "ReadHostedZone"
        Effect = "Allow"
        Action = [
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets",
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
  description = "CI policy foundation/read: read the state bucket, managed buckets, <name_root>-* IAM and ECR repositories, the GitHub OIDC provider and the hosted zone"
  policy      = jsonencode(local.policy)

  tags = {
    Component = "ci"
  }
}
