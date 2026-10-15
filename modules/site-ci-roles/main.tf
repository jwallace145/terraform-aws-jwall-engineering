data "aws_caller_identity" "current" {}

locals {
  component  = "site-ci-roles"
  account_id = data.aws_caller_identity.current.account_id
  name_root  = "jwall-engineering-${var.project}"

  role_names = {
    plan    = "${local.name_root}-ci-plan"
    preview = "${local.name_root}-ci-preview"
    apply   = "${local.name_root}-ci-apply"
  }

  # GitHub issues the `sub` claim in one of two shapes depending on the
  # repository's OIDC settings: the classic repo:<owner>/<name> and the
  # immutable repo:<owner>@<owner_id>/<name>@<repository_id>. Trust both when
  # the IDs are supplied so the roles work whichever form the repo uses.
  github_owner = split("/", var.repository)[0]
  github_name  = split("/", var.repository)[1]

  subject_prefixes = concat(
    ["repo:${var.repository}"],
    var.owner_id == null ? [] : ["repo:${local.github_owner}@${var.owner_id}/${local.github_name}@${var.repository_id}"],
  )

  # OIDC `sub` claims each role trusts.
  subjects = {
    plan    = [for p in local.subject_prefixes : "${p}:pull_request"]
    preview = [for p in local.subject_prefixes : "${p}:pull_request"]
    apply   = [for p in local.subject_prefixes : "${p}:environment:prod"]
  }

  state_prefix = "project=${var.project}/"

  # Route 53 normalises record names in the condition key: lowercase, with `*`
  # encoded as the octal escape `\052`.
  normalized_record_names = [for n in var.record_names : replace(lower(n), "*", "\\052")]

  # ACM DNS validation records are `_<token>.<domain>`; `_*.<domain>` covers them.
  # A wildcard record `*.preview.x` validates on `_<token>.preview.x`.
  acm_validation_record_names = distinct([
    for n in var.record_names : "_*.${replace(lower(n), "*.", "")}"
  ])

  route53_record_names = concat(local.normalized_record_names, local.acm_validation_record_names)

  zone_arn = "arn:aws:route53:::hostedzone/${var.zone_id}"

  project_tag_condition = {
    StringEquals = {
      "aws:ResourceTag/Project" = var.project
    }
  }

  cloudfront_distribution_arn = "arn:aws:cloudfront::${local.account_id}:distribution/*"
  cloudfront_function_arn     = "arn:aws:cloudfront::${local.account_id}:function/${local.name_root}-*"
  acm_certificate_arn         = "arn:aws:acm:us-east-1:${local.account_id}:certificate/*"

  # Read-only statements shared by the plan role and (as a subset) the apply role.
  read_statements = [
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
      Resource  = local.cloudfront_distribution_arn
      Condition = local.project_tag_condition
    },
    {
      Sid    = "ReadProjectFunctions"
      Effect = "Allow"
      Action = [
        "cloudfront:DescribeFunction",
        "cloudfront:GetFunction",
      ]
      Resource  = local.cloudfront_function_arn
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
      Resource  = local.acm_certificate_arn
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

  plan_policy = {
    Version = "2012-10-17"
    Statement = concat(local.read_statements, [
      {
        Sid      = "ListProjectState"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = var.state_bucket_arn
        Condition = {
          StringLike = {
            "s3:prefix" = "${local.state_prefix}*"
          }
        }
      },
      {
        Sid      = "ReadProjectState"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${var.state_bucket_arn}/${local.state_prefix}*"
      },
      {
        Sid    = "ManageProjectStateLocks"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "${var.state_bucket_arn}/${local.state_prefix}*.tflock"
      },
    ])
  }

  preview_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListPreviews"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = var.bucket_arn
        Condition = {
          StringLike = {
            "s3:prefix" = "previews/*"
          }
        }
      },
      {
        Sid    = "WritePreviews"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "${var.bucket_arn}/previews/*"
      },
    ]
  }

  apply_policy = {
    Version = "2012-10-17"
    Statement = concat(local.read_statements, [
      {
        Sid      = "ListProjectState"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = var.state_bucket_arn
        Condition = {
          StringLike = {
            "s3:prefix" = "${local.state_prefix}*"
          }
        }
      },
      {
        Sid    = "ReadWriteProjectState"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "${var.state_bucket_arn}/${local.state_prefix}*"
      },
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
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
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
        Sid      = "RequestProjectCertificates"
        Effect   = "Allow"
        Action   = "acm:RequestCertificate"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
          }
        }
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
            "route53:ChangeResourceRecordSetsNormalizedRecordNames" = local.route53_record_names
          }
        }
      },
    ])
  }

  policies = {
    plan    = local.plan_policy
    preview = local.preview_policy
    apply   = local.apply_policy
  }
}

resource "aws_iam_role" "this" {
  for_each = local.role_names

  name        = each.value
  description = "GitHub Actions ${each.key} role for ${var.repository} (${var.project})"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GitHubOidc"
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = local.subjects[each.key]
          }
        }
      },
    ]
  })

  tags = {
    Component = local.component
  }
}

resource "aws_iam_role_policy" "this" {
  for_each = local.policies

  name   = "${local.role_names[each.key]}-policy"
  role   = aws_iam_role.this[each.key].id
  policy = jsonencode(each.value)
}
