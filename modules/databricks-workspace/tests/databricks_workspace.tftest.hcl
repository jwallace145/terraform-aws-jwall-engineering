mock_provider "aws" {
  override_during = plan

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::jwall-engineering-databricks-poc-databricks-root"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111122223333:role/jwall-engineering-databricks-poc-databricks-cross-account"
    }
  }

  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-0123456789abcdef0"
    }
  }

  mock_data "aws_subnet" {
    defaults = {
      cidr_block = "10.0.2.0/24"
      vpc_id     = "vpc-0123456789abcdef0"
    }
  }
}

mock_provider "databricks" {
  override_during = plan

  mock_resource "databricks_group" {
    defaults = {
      id = "1111"
    }
  }

  mock_resource "databricks_mws_workspaces" {
    defaults = {
      workspace_id  = 1234567890123456
      workspace_url = "https://dbc-01234567-89ab.cloud.databricks.com"
    }
  }

  mock_data "databricks_service_principal" {
    defaults = {
      sp_id = "5555"
    }
  }

  mock_data "databricks_user" {
    defaults = {
      id = "7777"
    }
  }
}

mock_provider "time" {}

# Realistic outputs of the provider's policy helpers (databricks 1.142.0,
# captured by evaluating the data sources with these inputs), so the
# assertions below check what actually reaches IAM and S3.
override_data {
  target = data.databricks_aws_assume_role_policy.this
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sts:AssumeRole\",\"Principal\":{\"AWS\":\"arn:aws:iam::414351767826:root\"},\"Condition\":{\"StringEquals\":{\"sts:ExternalId\":\"11111111-2222-3333-4444-555555555555\"}}}]}"
  }
}

override_data {
  target = data.databricks_aws_crossaccount_policy.this
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"ec2:DescribeSubnets\",\"ec2:DescribeVpcs\",\"ec2:RunInstances\",\"ec2:TerminateInstances\"],\"Resource\":\"*\"},{\"Effect\":\"Allow\",\"Action\":[\"iam:CreateServiceLinkedRole\",\"iam:PutRolePolicy\"],\"Resource\":\"arn:aws:iam::*:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot\",\"Condition\":{\"StringLike\":{\"iam:AWSServiceName\":\"spot.amazonaws.com\"}}}]}"
  }
}

override_data {
  target = data.databricks_aws_bucket_policy.root
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:GetObjectVersion\",\"s3:PutObject\",\"s3:DeleteObject\",\"s3:ListBucket\",\"s3:GetBucketLocation\"],\"Resource\":[\"arn:aws:s3:::jwall-engineering-databricks-poc-databricks-root/*\",\"arn:aws:s3:::jwall-engineering-databricks-poc-databricks-root\"],\"Principal\":{\"AWS\":\"arn:aws:iam::414351767826:root\"},\"Condition\":{\"StringEquals\":{\"aws:PrincipalTag/DatabricksAccountId\":\"11111111-2222-3333-4444-555555555555\"}}}]}"
  }
}

override_resource {
  target          = databricks_group.users
  override_during = plan
  values = {
    id = "2222"
  }
}

variables {
  account_id   = "11111111-2222-3333-4444-555555555555"
  project      = "databricks-poc"
  environment  = "dev"
  vpc_id       = "vpc-0123456789abcdef0"
  subnet_ids   = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  metastore_id = "abcdef01-2345-6789-abcd-ef0123456789"
  tags = {
    Project     = "databricks-poc"
    Environment = "dev"
    CostCenter  = "cc-0000"
    Workspace   = "databricks-poc-dev"
    Owner       = "team-a"
    ManagedBy   = "terraform"
  }
  admin_user_names                 = ["owner@example.com"]
  user_names                       = ["analyst@example.com", "engineer@example.com"]
  service_principal_application_id = "00000000-0000-0000-0000-000000000000"
}

run "security_group_egress_ports" {
  command = plan

  assert {
    condition = toset([
      for e in aws_security_group.this.egress :
      "${e.protocol}:${e.from_port}-${e.to_port}"
      if e.cidr_blocks == tolist(["0.0.0.0/0"]) && e.self != true
    ]) == toset(["tcp:443-443", "tcp:3306-3306", "tcp:53-53", "tcp:6666-6666", "tcp:2443-2443", "tcp:5432-5432", "tcp:8443-8451"])
    error_message = "internet egress must be exactly the TCP ports on Databricks' customer-managed VPC page: 443, 3306, 53, 6666, 2443, 5432, 8443-8451"
  }

  assert {
    condition = length([
      for e in aws_security_group.this.egress : e
      if e.self == true && e.protocol == "-1" && e.from_port == 0 && e.to_port == 0 && length(coalesce(e.cidr_blocks, [])) == 0
    ]) == 1 && length(aws_security_group.this.egress) == 8
    error_message = "egress must be one all-protocol rule to the group itself plus the seven internet rules, nothing else"
  }

  assert {
    condition = length(aws_security_group.this.ingress) == 1 && alltrue([
      for i in aws_security_group.this.ingress :
      i.self == true && i.protocol == "-1" && i.from_port == 0 && i.to_port == 0 && length(coalesce(i.cidr_blocks, [])) == 0
    ])
    error_message = "the only ingress must be all protocols from the group itself"
  }

  assert {
    condition     = aws_security_group.this.name == "jwall-engineering-databricks-poc-databricks-workspace" && aws_security_group.this.vpc_id == var.vpc_id
    error_message = "the security group must be <p>-databricks-workspace in vpc_id"
  }

  assert {
    condition = (
      databricks_mws_networks.this.security_group_ids == toset(["sg-0123456789abcdef0"]) &&
      databricks_mws_networks.this.subnet_ids == toset(var.subnet_ids) &&
      databricks_mws_networks.this.vpc_id == var.vpc_id &&
      databricks_mws_networks.this.account_id == var.account_id
    )
    error_message = "the network configuration must use the module's security group, subnet_ids and vpc_id"
  }
}

run "cross_account_policy_is_customer_vpc_type" {
  command = plan

  assert {
    condition     = data.databricks_aws_crossaccount_policy.this.policy_type == "customer"
    error_message = "the cross-account policy must be the customer-managed VPC type"
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.cross_account.policy) == jsondecode(data.databricks_aws_crossaccount_policy.this.json) && aws_iam_role_policy.cross_account.role == aws_iam_role.cross_account.id
    error_message = "the cross-account role must carry exactly the helper's customer policy"
  }

  assert {
    condition = (
      data.databricks_aws_assume_role_policy.this.external_id == var.account_id &&
      length(jsondecode(aws_iam_role.cross_account.assume_role_policy).Statement) == 1 &&
      jsondecode(aws_iam_role.cross_account.assume_role_policy).Statement[0].Action == "sts:AssumeRole" &&
      jsondecode(aws_iam_role.cross_account.assume_role_policy).Statement[0].Principal.AWS == "arn:aws:iam::414351767826:root" &&
      jsondecode(aws_iam_role.cross_account.assume_role_policy).Statement[0].Condition.StringEquals["sts:ExternalId"] == var.account_id
    )
    error_message = "the role must trust Databricks only with sts:ExternalId = account_id (StringEquals)"
  }

  assert {
    condition     = aws_iam_role.cross_account.name == "jwall-engineering-databricks-poc-databricks-cross-account"
    error_message = "the cross-account role must be named <p>-databricks-cross-account"
  }

  assert {
    condition     = time_sleep.iam_propagation.create_duration == "20s" && databricks_mws_credentials.this.role_arn == aws_iam_role.cross_account.arn
    error_message = "credentials must use the cross-account role after a 20s IAM propagation wait"
  }
}

run "root_bucket_private_and_encrypted" {
  command = plan

  assert {
    condition     = aws_s3_bucket.root.bucket == "jwall-engineering-databricks-poc-databricks-root" && aws_s3_bucket.root.force_destroy
    error_message = "root bucket must be <p>-databricks-root with force_destroy"
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.root.block_public_acls &&
      aws_s3_bucket_public_access_block.root.block_public_policy &&
      aws_s3_bucket_public_access_block.root.ignore_public_acls &&
      aws_s3_bucket_public_access_block.root.restrict_public_buckets
    )
    error_message = "root bucket must block every form of public access"
  }

  assert {
    condition     = one([for r in aws_s3_bucket_server_side_encryption_configuration.root.rule : one(r.apply_server_side_encryption_by_default).sse_algorithm]) == "AES256"
    error_message = "root bucket must use SSE-S3 (AES256)"
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.root.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "root bucket must disable ACLs (BucketOwnerEnforced)"
  }

  assert {
    condition = (
      data.databricks_aws_bucket_policy.root.bucket == aws_s3_bucket.root.bucket &&
      data.databricks_aws_bucket_policy.root.databricks_e2_account_id == var.account_id &&
      jsondecode(aws_s3_bucket_policy.root.policy) == jsondecode(data.databricks_aws_bucket_policy.root.json)
    )
    error_message = "the bucket policy must be the helper's policy for this bucket, scoped to the account ID"
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_s3_bucket_policy.root.policy).Statement :
      s.Principal.AWS != "*" && s.Condition.StringEquals["aws:PrincipalTag/DatabricksAccountId"] == var.account_id
    ])
    error_message = "every bucket policy grant must name a principal and require the Databricks account ID tag"
  }

  assert {
    condition     = databricks_mws_storage_configurations.this.bucket_name == aws_s3_bucket.root.bucket && databricks_mws_storage_configurations.this.account_id == var.account_id
    error_message = "the storage configuration must point at the root bucket"
  }
}

run "workspace_tags_passthrough" {
  command = plan

  assert {
    condition     = databricks_mws_workspaces.this.custom_tags == var.tags
    error_message = "workspace custom_tags must be the tags input, unchanged"
  }

  assert {
    condition = (
      databricks_mws_workspaces.this.workspace_name == "databricks-poc-dev" &&
      databricks_mws_workspaces.this.pricing_tier == "PREMIUM" &&
      databricks_mws_workspaces.this.aws_region == "us-east-1" &&
      databricks_mws_workspaces.this.deployment_name == null
    )
    error_message = "workspace must be <project>-<environment>, PREMIUM, us-east-1, with no deployment_name unless given"
  }

  assert {
    condition     = databricks_metastore_assignment.this.metastore_id == var.metastore_id && databricks_metastore_assignment.this.workspace_id == 1234567890123456
    error_message = "the workspace must be assigned to metastore_id"
  }
}

run "deployment_name_passthrough" {
  command = plan

  variables {
    deployment_name = "databricks-poc-dev"
  }

  assert {
    condition     = databricks_mws_workspaces.this.deployment_name == "databricks-poc-dev"
    error_message = "deployment_name must be passed through when set"
  }
}

run "service_principal_is_workspace_admin" {
  command = plan

  assert {
    condition     = databricks_group.admins.display_name == "databricks-poc-workspace-admins"
    error_message = "admin group must be <project>-workspace-admins"
  }

  assert {
    condition     = data.databricks_service_principal.automation.application_id == var.service_principal_application_id
    error_message = "the service principal must be looked up by application_id"
  }

  assert {
    condition     = databricks_group_member.service_principal.group_id == "1111" && databricks_group_member.service_principal.member_id == "5555"
    error_message = "the service principal (sp_id) must be a member of the admin group"
  }

  assert {
    condition = (
      keys(databricks_group_member.admins) == ["owner@example.com"] &&
      alltrue([for m in databricks_group_member.admins : m.group_id == "1111" && m.member_id == "7777"])
    )
    error_message = "every admin user must be a member of the admin group"
  }

  assert {
    condition = (
      databricks_mws_permission_assignment.admins.principal_id == 1111 &&
      databricks_mws_permission_assignment.admins.permissions == toset(["ADMIN"]) &&
      databricks_mws_permission_assignment.admins.workspace_id == 1234567890123456
    )
    error_message = "the admin group must get ADMIN on the workspace"
  }
}

run "users_get_user_not_admin" {
  command = plan

  assert {
    condition     = databricks_group.users.display_name == "databricks-poc-workspace-users"
    error_message = "users group must be <project>-workspace-users"
  }

  assert {
    condition = (
      toset(keys(databricks_group_member.users)) == toset(var.user_names) &&
      alltrue([for m in databricks_group_member.users : m.group_id == "2222"])
    )
    error_message = "every user must be a member of the users group"
  }

  assert {
    condition = (
      databricks_mws_permission_assignment.users.principal_id == 2222 &&
      databricks_mws_permission_assignment.users.permissions == toset(["USER"]) &&
      databricks_mws_permission_assignment.users.workspace_id == 1234567890123456
    )
    error_message = "the users group must get USER, and only USER, on the workspace"
  }
}

run "outputs_feed_workspace_stack" {
  command = plan

  assert {
    condition = (
      output.workspace_url == "https://dbc-01234567-89ab.cloud.databricks.com" &&
      output.workspace_id == 1234567890123456 &&
      output.admin_group_name == "databricks-poc-workspace-admins" &&
      output.users_group_name == "databricks-poc-workspace-users" &&
      output.root_bucket_name == "jwall-engineering-databricks-poc-databricks-root" &&
      output.security_group_id == "sg-0123456789abcdef0" &&
      output.cross_account_role_arn == "arn:aws:iam::111122223333:role/jwall-engineering-databricks-poc-databricks-cross-account"
    )
    error_message = "outputs must expose the workspace, groups, bucket, security group and role"
  }
}

run "rejects_one_subnet" {
  command = plan

  variables {
    subnet_ids = ["subnet-0123456789abcdef0"]
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_missing_cost_center_tag" {
  command = plan

  variables {
    tags = {
      Project     = "databricks-poc"
      Environment = "dev"
      Workspace   = "databricks-poc-dev"
      Owner       = "team-a"
      ManagedBy   = "terraform"
    }
  }

  expect_failures = [var.tags]
}

run "rejects_reserved_tag_key" {
  command = plan

  variables {
    tags = {
      Project     = "databricks-poc"
      Environment = "dev"
      CostCenter  = "cc-0000"
      Workspace   = "databricks-poc-dev"
      Owner       = "team-a"
      ManagedBy   = "terraform"
      Vendor      = "someone"
    }
  }

  expect_failures = [var.tags]
}

run "rejects_subnet_netmask_27" {
  command = plan

  override_data {
    target = data.aws_subnet.this
    values = {
      cidr_block = "10.0.0.0/27"
      vpc_id     = "vpc-0123456789abcdef0"
    }
  }

  expect_failures = [data.aws_subnet.this]
}

run "accepts_subnet_netmask_26" {
  command = plan

  override_data {
    target = data.aws_subnet.this
    values = {
      cidr_block = "10.0.0.0/26"
      vpc_id     = "vpc-0123456789abcdef0"
    }
  }

  assert {
    condition     = length(data.aws_subnet.this) == 2
    error_message = "a /26 subnet is the smallest Databricks accepts and must pass the check"
  }
}

run "rejects_subnet_outside_vpc" {
  command = plan

  override_data {
    target = data.aws_subnet.this
    values = {
      cidr_block = "10.1.2.0/24"
      vpc_id     = "vpc-0fedcba9876543210"
    }
  }

  expect_failures = [data.aws_subnet.this]
}

run "rejects_long_project" {
  command = plan

  variables {
    project = "abcdefghijklmnopqrstuv"
  }

  expect_failures = [var.project]
}

run "rejects_long_workspace_name" {
  command = plan

  variables {
    project     = "databricks-poc-team-a"
    environment = "staging-01"
  }

  expect_failures = [var.environment]
}

run "rejects_bad_deployment_name" {
  command = plan

  variables {
    deployment_name = "Databricks_POC"
  }

  expect_failures = [var.deployment_name]
}
