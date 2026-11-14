# Composition test: the Databricks modules wired together the way the account
# stack (vpc, nat-instance, databricks-workspace) and the workspace stack
# (databricks-catalog, databricks-workspace-config) wire them. Each module has
# its own tests; this one checks that their outputs and inputs fit.
mock_provider "aws" {
  override_during = plan

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::jwall-engineering-databricks-poc-databricks-root"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::111122223333:role/jwall-engineering-databricks-poc-databricks-uc"
    }
  }

  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-0123456789abcdef0"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
    }
  }

  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
    }
  }

  mock_data "aws_subnet" {
    defaults = {
      cidr_block = "10.0.128.0/20"
      vpc_id     = "vpc-0123456789abcdef0"
    }
  }
}

mock_provider "databricks" {
  alias           = "account"
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

mock_provider "databricks" {
  alias           = "workspace"
  override_during = plan

  mock_data "databricks_group" {
    defaults = {
      id = "1111"
    }
  }
}

mock_provider "time" {}

# Realistic outputs of the provider's policy helpers (see the module tests),
# as the mock would return invalid documents.
override_data {
  target          = module.workspace.data.databricks_aws_assume_role_policy.this
  override_during = plan
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sts:AssumeRole\",\"Principal\":{\"AWS\":\"arn:aws:iam::414351767826:root\"},\"Condition\":{\"StringEquals\":{\"sts:ExternalId\":\"11111111-2222-3333-4444-555555555555\"}}}]}"
  }
}

override_data {
  target          = module.workspace.data.databricks_aws_crossaccount_policy.this
  override_during = plan
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"ec2:DescribeSubnets\",\"ec2:DescribeVpcs\",\"ec2:RunInstances\",\"ec2:TerminateInstances\"],\"Resource\":\"*\"},{\"Effect\":\"Allow\",\"Action\":[\"iam:CreateServiceLinkedRole\",\"iam:PutRolePolicy\"],\"Resource\":\"arn:aws:iam::*:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot\",\"Condition\":{\"StringLike\":{\"iam:AWSServiceName\":\"spot.amazonaws.com\"}}}]}"
  }
}

override_data {
  target          = module.workspace.data.databricks_aws_bucket_policy.root
  override_during = plan
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:GetObjectVersion\",\"s3:PutObject\",\"s3:DeleteObject\",\"s3:ListBucket\",\"s3:GetBucketLocation\"],\"Resource\":[\"arn:aws:s3:::jwall-engineering-databricks-poc-databricks-root/*\",\"arn:aws:s3:::jwall-engineering-databricks-poc-databricks-root\"],\"Principal\":{\"AWS\":\"arn:aws:iam::414351767826:root\"},\"Condition\":{\"StringEquals\":{\"aws:PrincipalTag/DatabricksAccountId\":\"11111111-2222-3333-4444-555555555555\"}}}]}"
  }
}

override_data {
  target          = module.catalog.data.databricks_aws_unity_catalog_policy.uc
  override_during = plan
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:PutObject\",\"s3:DeleteObject\",\"s3:ListBucket\"],\"Resource\":[\"arn:aws:s3:::jwall-engineering-databricks-poc-databricks-catalog/*\",\"arn:aws:s3:::jwall-engineering-databricks-poc-databricks-catalog\"]}]}"
  }
}

# The plan itself is the check that the modules accept IDs that are unknown
# until apply (the subnets, the VPC, the instance's interface).
run "compose" {
  command = plan

  module {
    source = "./tests/stacks"
  }

  assert {
    condition = contains(flatten([
      for s in jsondecode(output.endpoint_policy).Statement : s.Resource if s.Sid == "UnityCatalogOnly"
      ]), "arn:aws:s3:::${output.catalog_bucket_name}") && contains(flatten([
      for s in jsondecode(output.endpoint_policy).Statement : s.Resource if s.Sid == "UnityCatalogOnly"
    ]), "arn:aws:s3:::${output.catalog_bucket_name}/*")
    error_message = "the endpoint policy's Unity Catalog statement must name the catalog bucket databricks-catalog creates"
  }

  assert {
    condition = one([
      for s in jsondecode(output.endpoint_policy).Statement : s.Condition.ArnEquals["aws:PrincipalArn"] if s.Sid == "UnityCatalogOnly"
    ]) == output.catalog_uc_role_arn
    error_message = "the endpoint policy must restrict the catalog bucket to the Unity Catalog role databricks-catalog creates"
  }
}

# With the vpc's IDs known, the wiring can be compared. (Child module
# resources are out of a test's reach, so this goes through outputs.)
run "nat_routes_on_the_endpoint_table" {
  command = plan

  module {
    source = "./tests/stacks"
  }

  override_resource {
    target          = module.network.aws_route_table.private[0]
    override_during = plan
    values          = { id = "rtb-0aaaaaaaaaaaaaaaa" }
  }

  override_resource {
    target          = module.network.aws_route_table.public
    override_during = plan
    values          = { id = "rtb-0bbbbbbbbbbbbbbbb" }
  }

  override_resource {
    target          = module.network.aws_vpc_endpoint.s3[0]
    override_during = plan
    values          = { id = "vpce-0123456789abcdef0" }
  }

  assert {
    condition     = output.s3_endpoint_id != null && output.private_route_table_id == "rtb-0aaaaaaaaaaaaaaaa" && output.private_route_table_id != output.public_route_table_id
    error_message = "the S3 endpoint must exist and sit on the private route table, not the public one"
  }

  assert {
    condition     = output.nat_route_table_ids == [output.private_route_table_id]
    error_message = "the NAT's default routes must go on the private route table, the one the S3 endpoint is associated with"
  }
}
