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

  # Existing project network resources the endpoint, the NAT's ENI, its
  # Elastic IP and its routes touch.
  network_types = ["vpc", "subnet", "route-table", "security-group", "vpc-endpoint", "network-interface", "elastic-ip"]

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
        Sid       = "CreateNatNetworkResources"
        Effect    = "Allow"
        Action    = ["ec2:CreateNetworkInterface", "ec2:AllocateAddress"]
        Resource  = ["${local.ec2}:network-interface/*", "${local.ec2}:elastic-ip/*"]
        Condition = local.request_tag
      },
      {
        # The endpoint in the project VPC on its route tables; the ENI in a
        # project subnet and security group, its source/dest check, the
        # Elastic IP on it, and routes whose target is the ENI.
        Sid    = "ManageInProjectNetwork"
        Effect = "Allow"
        Action = [
          "ec2:CreateVpcEndpoint",
          "ec2:ModifyVpcEndpoint",
          "ec2:DeleteVpcEndpoints",
          "ec2:CreateNetworkInterface",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:DeleteNetworkInterface",
          "ec2:AssociateAddress",
          "ec2:DisassociateAddress",
          "ec2:ReleaseAddress",
          "ec2:CreateRoute",
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
          StringLike = { "ec2:InstanceType" = "t4g.*" }
        }
      },
      {
        # The provider tags the root volume after launch, so the request may
        # carry no volume tags. The volume exists only with an instance that
        # passes RunNatInstance.
        Sid      = "RunNatVolume"
        Effect   = "Allow"
        Action   = "ec2:RunInstances"
        Resource = "${local.ec2}:volume/*"
      },
      {
        Sid       = "RunFromAmazonImages"
        Effect    = "Allow"
        Action    = "ec2:RunInstances"
        Resource  = "arn:aws:ec2:${local.region}::image/*"
        Condition = { StringEquals = { "ec2:Owner" = "amazon" } }
      },
      {
        # The NAT launches on its existing ENI, in its subnet and group.
        Sid    = "RunNatInProjectNetwork"
        Effect = "Allow"
        Action = "ec2:RunInstances"
        Resource = [
          "${local.ec2}:subnet/*",
          "${local.ec2}:security-group/*",
          "${local.ec2}:network-interface/*",
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
        Sid    = "TagOnCreate"
        Effect = "Allow"
        Action = "ec2:CreateTags"
        Resource = [
          "${local.ec2}:vpc-endpoint/*",
          "${local.ec2}:network-interface/*",
          "${local.ec2}:elastic-ip/*",
          "${local.ec2}:instance/*",
          "${local.ec2}:volume/*",
        ]
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = ["CreateVpcEndpoint", "CreateNetworkInterface", "AllocateAddress", "RunInstances"]
          }
        }
      },
      {
        # root_block_device tags are applied by a CreateTags call after
        # launch, to a volume with no tags yet. Later changes go through
        # compute/manage's ManageProjectTags.
        Sid       = "TagNatRootVolume"
        Effect    = "Allow"
        Action    = "ec2:CreateTags"
        Resource  = "${local.ec2}:volume/*"
        Condition = { StringEquals = { "aws:RequestTag/Component" = "nat-instance" } }
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
