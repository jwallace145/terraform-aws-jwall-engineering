data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  prefix     = "${var.name_root}-${var.project}"
  ec2        = "arn:aws:ec2:${local.region}:${local.account_id}"

  request_tag  = { StringEquals = { "aws:RequestTag/Project" = var.project } }
  resource_tag = { StringEquals = { "aws:ResourceTag/Project" = var.project } }

  network_types = ["vpc", "subnet", "internet-gateway", "route-table", "security-group", "security-group-rule"]

  create_actions = [
    "CreateVpc",
    "CreateSubnet",
    "CreateInternetGateway",
    "CreateRouteTable",
    "CreateSecurityGroup",
    "RunInstances",
  ]

  # Write-only: pair with container/read, which the apply role also needs
  # for refresh.
  policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CreateProjectNetwork"
        Effect = "Allow"
        Action = [
          "ec2:CreateVpc",
          "ec2:CreateSubnet",
          "ec2:CreateInternetGateway",
          "ec2:CreateRouteTable",
          "ec2:CreateSecurityGroup",
        ]
        Resource  = [for t in local.network_types : "${local.ec2}:${t}/*"]
        Condition = local.request_tag
      },
      {
        # Creating a subnet, security group or route table also authorizes
        # against the parent VPC, which must be the project's.
        Sid    = "CreateInsideProjectVpc"
        Effect = "Allow"
        Action = [
          "ec2:CreateSubnet",
          "ec2:CreateSecurityGroup",
          "ec2:CreateRouteTable",
          "ec2:AttachInternetGateway",
        ]
        Resource  = "${local.ec2}:vpc/*"
        Condition = local.resource_tag
      },
      {
        Sid    = "ManageProjectNetwork"
        Effect = "Allow"
        Action = [
          "ec2:ModifyVpcAttribute",
          "ec2:DeleteVpc",
          "ec2:DeleteSubnet",
          "ec2:ModifySubnetAttribute",
          "ec2:DeleteInternetGateway",
          "ec2:AttachInternetGateway",
          "ec2:DetachInternetGateway",
          "ec2:CreateRoute",
          "ec2:DeleteRoute",
          "ec2:DeleteRouteTable",
          "ec2:AssociateRouteTable",
          "ec2:DisassociateRouteTable",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DeleteSecurityGroup",
          "ec2:ModifySecurityGroupRules",
        ]
        Resource  = [for t in local.network_types : "${local.ec2}:${t}/*"]
        Condition = local.resource_tag
      },
      {
        Sid    = "RunProjectInstances"
        Effect = "Allow"
        Action = "ec2:RunInstances"
        Resource = [
          "${local.ec2}:instance/*",
          "${local.ec2}:volume/*",
        ]
        Condition = local.request_tag
      },
      {
        # The other resources RunInstances authorizes against. The image is
        # a public Amazon image, so it is not in this account.
        Sid    = "RunInstancesDependencies"
        Effect = "Allow"
        Action = "ec2:RunInstances"
        Resource = [
          "arn:aws:ec2:${local.region}::image/*",
          "${local.ec2}:network-interface/*",
          "${local.ec2}:subnet/*",
          "${local.ec2}:security-group/*",
        ]
      },
      {
        Sid    = "ManageProjectInstances"
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances",
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:ModifyInstanceAttribute",
          "ec2:ModifyInstanceMetadataOptions",
          "ec2:ModifyInstanceCreditSpecification",
          "ec2:MonitorInstances",
          "ec2:UnmonitorInstances",
        ]
        Resource  = "${local.ec2}:instance/*"
        Condition = local.resource_tag
      },
      {
        # Gap: tags applied by a create call. Bounded to those create calls.
        Sid       = "CreateTagsOnCreate"
        Effect    = "Allow"
        Action    = "ec2:CreateTags"
        Resource  = "*"
        Condition = { StringEquals = { "ec2:CreateAction" = local.create_actions } }
      },
      {
        # Gap: tag changes on existing resources, bounded by the Project tag.
        Sid    = "ManageProjectTags"
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:DeleteTags",
        ]
        Resource  = "*"
        Condition = local.resource_tag
      },
      {
        Sid    = "ManageProjectRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:UpdateRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:DetachRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:UntagInstanceProfile",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:TagPolicy",
          "iam:UntagPolicy",
        ]
        Resource = [
          "arn:aws:iam::${local.account_id}:role/${local.prefix}-*",
          "arn:aws:iam::${local.account_id}:instance-profile/${local.prefix}-*",
          "arn:aws:iam::${local.account_id}:policy/${local.prefix}-*",
        ]
      },
      {
        Sid      = "AttachProjectRolePolicies"
        Effect   = "Allow"
        Action   = "iam:AttachRolePolicy"
        Resource = "arn:aws:iam::${local.account_id}:role/${local.prefix}-*"
        Condition = {
          ArnLike = {
            "iam:PolicyARN" = concat(
              [
                "arn:aws:iam::${local.account_id}:policy/${local.prefix}-*",
                "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
              ],
              var.attachable_policy_arns,
            )
          }
        }
      },
      {
        Sid       = "PassInstanceRole"
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = "arn:aws:iam::${local.account_id}:role/${local.prefix}-*"
        Condition = { StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" } }
      },
      {
        Sid    = "ManageProjectImageRepository"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository",
          "ecr:DeleteRepository",
          "ecr:PutImageTagMutability",
          "ecr:PutImageScanningConfiguration",
          "ecr:PutLifecyclePolicy",
          "ecr:DeleteLifecyclePolicy",
          "ecr:SetRepositoryPolicy",
          "ecr:DeleteRepositoryPolicy",
          "ecr:TagResource",
          "ecr:UntagResource",
        ]
        Resource = "arn:aws:ecr:${local.region}:${local.account_id}:repository/${local.prefix}"
      },
      {
        Sid    = "ManageProjectLogGroups"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy",
          "logs:DeleteRetentionPolicy",
          "logs:TagResource",
          "logs:UntagResource",
          "logs:TagLogGroup",
          "logs:UntagLogGroup",
        ]
        Resource = [
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:/${var.name_root}/${var.project}/*",
        ]
      },
      {
        # Tags only. Parameter values are written by the instance and the
        # release role, and the secret by the owner; never by Terraform.
        Sid    = "ManageProjectParameterTags"
        Effect = "Allow"
        Action = [
          "ssm:AddTagsToResource",
          "ssm:RemoveTagsFromResource",
        ]
        Resource = "arn:aws:ssm:${local.region}:${local.account_id}:parameter/${var.name_root}/${var.project}/*"
      },
      {
        # Bucket configuration only; never its objects.
        Sid    = "ManageRecordsBucket"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:PutBucketVersioning",
          "s3:PutEncryptionConfiguration",
          "s3:PutLifecycleConfiguration",
          "s3:PutBucketPublicAccessBlock",
          "s3:PutBucketOwnershipControls",
          "s3:PutBucketTagging",
          "s3:PutBucketAcl",
        ]
        Resource = "arn:aws:s3:::${local.prefix}-records"
      },
    ]
  }
}

resource "aws_iam_policy" "this" {
  name        = var.name
  description = "CI policy container/manage: create and manage the project's network, instance, instance role, image repository, parameters, log group and records bucket"
  policy      = jsonencode(local.policy)

  tags = {
    Component = "ci"
  }
}
