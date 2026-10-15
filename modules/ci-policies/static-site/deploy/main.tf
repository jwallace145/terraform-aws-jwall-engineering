data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  zone_arn   = "arn:aws:route53:::hostedzone/${var.zone_id}"

  # Route 53 normalises record names in the condition key: lowercase, with `*`
  # encoded as the octal escape `\052`.
  normalized_record_names = [for n in var.record_names : replace(lower(n), "*", "\\052")]

  # ACM DNS validation records are `_<token>.<domain>`; `_*.<domain>` covers them.
  # A wildcard record `*.preview.x` validates on `_<token>.preview.x`.
  acm_validation_record_names = distinct([
    for n in var.record_names : "_*.${replace(lower(n), "*.", "")}"
  ])

  project_tag_condition = {
    StringEquals = {
      "aws:ResourceTag/Project" = var.project
    }
  }

  project_request_tag_condition = {
    StringEquals = {
      "aws:RequestTag/Project" = var.project
    }
  }

  cloudfront_distribution_arn = "arn:aws:cloudfront::${local.account_id}:distribution/*"
  cloudfront_function_arn     = "arn:aws:cloudfront::${local.account_id}:function/${var.name_root}-${var.project}-*"
  acm_certificate_arn         = "arn:aws:acm:us-east-1:${local.account_id}:certificate/*"

  # Write-only: pair with static-site/read, which the apply role also needs
  # for refresh.
  policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListSiteContent"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = var.bucket_arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["prod/*", "dev/*"]
          }
        }
      },
      {
        Sid    = "WriteSiteContent"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = [
          "${var.bucket_arn}/prod/*",
          "${var.bucket_arn}/dev/*",
        ]
      },
      {
        Sid    = "CreateProjectDistributions"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateDistribution",
          "cloudfront:CreateFunction",
        ]
        Resource  = "*"
        Condition = local.project_request_tag_condition
      },
      {
        Sid    = "ManageProjectDistributions"
        Effect = "Allow"
        Action = [
          "cloudfront:UpdateDistribution",
          "cloudfront:DeleteDistribution",
          "cloudfront:TagResource",
          "cloudfront:UntagResource",
          "cloudfront:CreateInvalidation",
        ]
        Resource  = local.cloudfront_distribution_arn
        Condition = local.project_tag_condition
      },
      {
        Sid    = "ManageProjectFunctions"
        Effect = "Allow"
        Action = [
          "cloudfront:UpdateFunction",
          "cloudfront:PublishFunction",
          "cloudfront:TestFunction",
          "cloudfront:DeleteFunction",
          "cloudfront:TagResource",
          "cloudfront:UntagResource",
        ]
        Resource  = local.cloudfront_function_arn
        Condition = local.project_tag_condition
      },
      {
        # Gap: origin access controls and cache policies are untaggable and
        # have random IDs. These actions cannot be scoped to the project.
        Sid    = "ManageUntaggableCloudFrontResources"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateOriginAccessControl",
          "cloudfront:UpdateOriginAccessControl",
          "cloudfront:DeleteOriginAccessControl",
          "cloudfront:CreateCachePolicy",
          "cloudfront:UpdateCachePolicy",
          "cloudfront:DeleteCachePolicy",
        ]
        Resource = "*"
      },
      {
        Sid       = "RequestProjectCertificates"
        Effect    = "Allow"
        Action    = "acm:RequestCertificate"
        Resource  = "*"
        Condition = local.project_request_tag_condition
      },
      {
        Sid    = "ManageProjectCertificates"
        Effect = "Allow"
        Action = [
          "acm:DeleteCertificate",
          "acm:AddTagsToCertificate",
          "acm:RemoveTagsFromCertificate",
          "acm:RenewCertificate",
        ]
        Resource  = local.acm_certificate_arn
        Condition = local.project_tag_condition
      },
      {
        Sid      = "ChangeProjectRecords"
        Effect   = "Allow"
        Action   = "route53:ChangeResourceRecordSets"
        Resource = local.zone_arn
        Condition = {
          "ForAllValues:StringLike" = {
            "route53:ChangeResourceRecordSetsNormalizedRecordNames" = concat(local.normalized_record_names, local.acm_validation_record_names)
          }
        }
      },
    ]
  }
}

resource "aws_iam_policy" "this" {
  name        = var.name
  description = "CI policy static-site/deploy: manage the project's distributions, functions, certificates and records, and publish prod/ and dev/"
  policy      = jsonencode(local.policy)

  tags = {
    Component = "ci"
  }
}
