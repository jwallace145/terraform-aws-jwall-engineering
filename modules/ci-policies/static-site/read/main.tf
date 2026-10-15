data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  zone_arn   = "arn:aws:route53:::hostedzone/${var.zone_id}"

  project_tag_condition = {
    StringEquals = {
      "aws:ResourceTag/Project" = var.project
    }
  }

  policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSiteBucketConfig"
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
        Resource = var.bucket_arn
      },
      {
        Sid    = "ReadProjectDistributions"
        Effect = "Allow"
        Action = [
          "cloudfront:GetDistribution",
          "cloudfront:GetDistributionConfig",
          "cloudfront:ListTagsForResource",
          "cloudfront:ListInvalidations",
          "cloudfront:GetInvalidation",
        ]
        Resource  = "arn:aws:cloudfront::${local.account_id}:distribution/*"
        Condition = local.project_tag_condition
      },
      {
        Sid    = "ReadProjectFunctions"
        Effect = "Allow"
        Action = [
          "cloudfront:DescribeFunction",
          "cloudfront:GetFunction",
          "cloudfront:ListTagsForResource",
        ]
        Resource  = "arn:aws:cloudfront::${local.account_id}:function/${var.name_root}-${var.project}-*"
        Condition = local.project_tag_condition
      },
      {
        # OAC, cache policies and response headers policies cannot be tagged and
        # have random IDs, so their read actions cannot be scoped to the project.
        Sid    = "ReadUntaggableCloudFrontResources"
        Effect = "Allow"
        Action = [
          "cloudfront:GetOriginAccessControl",
          "cloudfront:GetOriginAccessControlConfig",
          "cloudfront:GetCachePolicy",
          "cloudfront:GetCachePolicyConfig",
          "cloudfront:GetResponseHeadersPolicy",
          "cloudfront:GetResponseHeadersPolicyConfig",
        ]
        Resource = "*"
      },
      {
        # List* actions have no resource-level support in CloudFront or ACM.
        Sid    = "ListCloudFrontAndAcm"
        Effect = "Allow"
        Action = [
          "cloudfront:ListDistributions",
          "cloudfront:ListFunctions",
          "cloudfront:ListOriginAccessControls",
          "cloudfront:ListCachePolicies",
          "cloudfront:ListResponseHeadersPolicies",
          "acm:ListCertificates",
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadProjectCertificates"
        Effect = "Allow"
        Action = [
          "acm:DescribeCertificate",
          "acm:GetCertificate",
          "acm:ListTagsForCertificate",
        ]
        Resource  = "arn:aws:acm:us-east-1:${local.account_id}:certificate/*"
        Condition = local.project_tag_condition
      },
      {
        Sid    = "ReadHostedZone"
        Effect = "Allow"
        Action = [
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets",
        ]
        Resource = local.zone_arn
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
  description = "CI policy static-site/read: read the project's site bucket, distributions, functions, certificates and hosted zone"
  policy      = jsonencode(local.policy)

  tags = {
    Component = "ci"
  }
}
