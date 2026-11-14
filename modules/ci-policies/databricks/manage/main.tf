data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  prefix     = "${var.name_root}-${var.project}"
  ec2        = "arn:aws:ec2:${local.region}:${local.account_id}"

  bucket_arns = [
    "arn:aws:s3:::${local.prefix}-databricks-root",
    "arn:aws:s3:::${local.prefix}-databricks-catalog",
  ]

  request_tag  = { StringEquals = { "aws:RequestTag/Project" = var.project } }
  resource_tag = { StringEquals = { "aws:ResourceTag/Project" = var.project } }

  # Existing project resources the S3 endpoint and the NAT's routes touch.
  network_types = ["vpc", "route-table", "vpc-endpoint"]

  # Write-only: pair with databricks/read, compute/read and compute/manage.
  # compute/manage already creates and changes the VPC, subnets, route tables,
  # routes on them and security groups (Project tag), and every
  # <name_root>-<project>-* role and inline policy, which covers the
  # -databricks- roles. This adds what the vpc (endpoint), nat-instance,
  # databricks-workspace and databricks-catalog modules create beyond that.
  policy = {
    Version = "2012-10-17"
    Statement = [
      {
        # Bucket configuration only.
        Sid    = "ManageDatabricksBuckets"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:PutEncryptionConfiguration",
          "s3:PutBucketPublicAccessBlock",
          "s3:PutBucketOwnershipControls",
          "s3:PutBucketTagging",
        ]
        Resource = local.bucket_arns
      },
      {
        # force_destroy empties both buckets. The catalog bucket's backstop
        # runs after its bucket policy is destroyed, so it relies on this.
        Sid      = "ListDatabricksBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:ListBucketVersions"]
        Resource = local.bucket_arns
      },
      {
        # Delete, never read or put: emptying needs nothing else.
        Sid      = "EmptyDatabricksBuckets"
        Effect   = "Allow"
        Action   = ["s3:DeleteObject", "s3:DeleteObjectVersion"]
        Resource = [for b in local.bucket_arns : "${b}/*"]
      },
      {
        Sid      = "CreateS3Endpoint"
        Effect   = "Allow"
        Action   = "ec2:CreateVpcEndpoint"
        Resource = "${local.ec2}:vpc-endpoint/*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project" = var.project
            "ec2:VpceServiceName"    = "com.amazonaws.us-east-1.s3"
          }
        }
      },
      {
        # The endpoint in the project VPC on its route tables, and replacing
        # the target of a route (the NAT's interface changes when the instance
        # is replaced). CreateRoute and ReplaceRoute authorize the route
        # table only, never the target interface.
        Sid    = "ManageInProjectNetwork"
        Effect = "Allow"
        Action = [
          "ec2:CreateVpcEndpoint",
          "ec2:ModifyVpcEndpoint",
          "ec2:DeleteVpcEndpoints",
          "ec2:ReplaceRoute",
        ]
        Resource  = [for t in local.network_types : "${local.ec2}:${t}/*"]
        Condition = local.resource_tag
      },
      {
        Sid      = "RunNatInstance"
        Effect   = "Allow"
        Action   = "ec2:RunInstances"
        Resource = "${local.ec2}:instance/*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/Project"   = var.project
            "aws:RequestTag/Component" = "nat-instance"
          }
          StringLike = { "ec2:InstanceType" = ["t4g.*", "c7g.*", "c8g.*", "m7g.*"] }
        }
      },
      {
        # The provider sets source_dest_check = false right after launch.
        Sid      = "ModifyNatInstance"
        Effect   = "Allow"
        Action   = "ec2:ModifyInstanceAttribute"
        Resource = "${local.ec2}:instance/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project"   = var.project
            "aws:ResourceTag/Component" = "nat-instance"
          }
        }
      },
      {
        # The launch tags the root volume with the provider default tags
        # (TagSpecifications). The provider then makes a second, post-launch
        # CreateTags call with the root_block_device tags; compute/manage's
        # ManageProjectTags authorizes that one.
        Sid       = "RunNatVolume"
        Effect    = "Allow"
        Action    = "ec2:RunInstances"
        Resource  = "${local.ec2}:volume/*"
        Condition = local.request_tag
      },
      {
        # The launch creates the primary interface, untagged: it is bounded
        # by the instance, subnet and security group statements.
        Sid      = "RunNatInterface"
        Effect   = "Allow"
        Action   = "ec2:RunInstances"
        Resource = "${local.ec2}:network-interface/*"
      },
      {
        Sid       = "RunFromAmazonImages"
        Effect    = "Allow"
        Action    = "ec2:RunInstances"
        Resource  = "arn:aws:ec2:${local.region}::image/*"
        Condition = { StringEquals = { "ec2:Owner" = "amazon" } }
      },
      {
        Sid    = "RunNatInProjectNetwork"
        Effect = "Allow"
        Action = "ec2:RunInstances"
        Resource = [
          "${local.ec2}:subnet/*",
          "${local.ec2}:security-group/*",
        ]
        Condition = local.resource_tag
      },
      {
        Sid      = "TerminateNatInstance"
        Effect   = "Allow"
        Action   = "ec2:TerminateInstances"
        Resource = "${local.ec2}:instance/*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project"   = var.project
            "aws:ResourceTag/Component" = "nat-instance"
          }
        }
      },
      {
        # The provider also tags the root volume after launch, with no
        # ec2:CreateAction. The volume already carries Project from the launch,
        # so that call goes through compute/manage's ManageProjectTags.
        Sid    = "TagOnCreate"
        Effect = "Allow"
        Action = "ec2:CreateTags"
        Resource = [
          "${local.ec2}:vpc-endpoint/*",
          "${local.ec2}:instance/*",
          "${local.ec2}:volume/*",
        ]
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = ["CreateVpcEndpoint", "RunInstances"]
          }
        }
      },
      {
        Sid      = "ReadSecret"
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = var.secret_parameter_arn
      },
      {
        # Parameter Store encrypts a SecureString with the parameter's ARN as
        # encryption context, so this decrypts that one parameter only.
        Sid      = "DecryptSecretThroughSsm"
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = "arn:aws:kms:${local.region}:${local.account_id}:key/*"
        Condition = {
          StringEquals = {
            "kms:EncryptionContext:PARAMETER_ARN" = var.secret_parameter_arn
            "kms:ViaService"                      = "ssm.us-east-1.amazonaws.com"
          }
        }
      },
      {
        # Append-only: no read, no delete.
        Sid      = "AppendEvents"
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = var.events_object_arn
      },
    ]
  }
}

resource "aws_iam_policy" "this" {
  name        = var.name
  description = "CI policy databricks/manage: create and manage the project's Databricks workspace infrastructure"
  policy      = jsonencode(local.policy)

  tags = {
    Component = "ci"
  }
}
