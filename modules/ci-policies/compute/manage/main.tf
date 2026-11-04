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
    "AuthorizeSecurityGroupEgress",
    "AuthorizeSecurityGroupIngress",
  ]

  # Write-only: pair with compute/read, which the apply role also needs
  # for refresh. The statements are copied from container/manage, for projects
  # with no bot; a test in ci-policies keeps them equal.
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
        # A rule created with tags is a new security-group-rule resource,
        # authorised by its request tags. The parent security group is
        # covered by ManageProjectNetwork.
        Sid    = "CreateProjectSecurityGroupRules"
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:AuthorizeSecurityGroupIngress",
        ]
        Resource  = "${local.ec2}:security-group-rule/*"
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
        Sid       = "PassInstanceRole"
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = "arn:aws:iam::${local.account_id}:role/${local.prefix}-*"
        Condition = { StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" } }
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
        ]
        Resource = [
          "arn:aws:logs:${local.region}:${local.account_id}:log-group:/${var.name_root}/${var.project}/*",
        ]
      },
    ]
  }
}

resource "aws_iam_policy" "this" {
  name        = var.name
  description = "CI policy compute/manage: create and manage the project's network, instance role and log groups"
  policy      = jsonencode(local.policy)

  tags = {
    Component = "ci"
  }
}
