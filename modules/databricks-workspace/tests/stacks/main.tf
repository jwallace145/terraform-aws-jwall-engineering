# Test fixture for stacks.tftest.hcl: the Databricks modules
# composed the way the two stacks (account, then workspace) compose them.
# Never applied; the test plans it against mock providers.
terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = ">= 1.142, < 2.0"
    }
  }
}

# Unconfigured; the test replaces both with mocks.
provider "databricks" {
  alias = "account"
}

provider "databricks" {
  alias = "workspace"
}

locals {
  tags = {
    Project     = "databricks-poc"
    Environment = "dev"
    CostCenter  = "cc-0000"
    Workspace   = "databricks-poc-dev"
    Owner       = "team-a"
    ManagedBy   = "terraform"
  }

  # The NAT's default routes go on the table the S3 endpoint is associated with.
  nat_route_table_ids = [module.network.private_route_table_id]
}

# ------------------------------------------------------------ account stack

module "workspace" {
  source = "../../"

  providers = {
    databricks = databricks.account
  }

  account_id   = "11111111-2222-3333-4444-555555555555"
  project      = "databricks-poc"
  environment  = "dev"
  vpc_id       = module.network.vpc_id
  subnet_ids   = module.network.private_subnet_ids
  metastore_id = "abcdef01-2345-6789-abcd-ef0123456789"
  tags         = local.tags

  admin_user_names                 = ["owner@example.com"]
  user_names                       = ["analyst@example.com"]
  service_principal_application_id = "00000000-0000-0000-0000-000000000000"
}

module "network" {
  source = "../../../vpc"

  name                 = "jwall-engineering-databricks-poc"
  availability_zones   = ["us-east-1a", "us-east-1b"]
  private_subnet_cidrs = ["10.0.128.0/20", "10.0.144.0/20"]

  # The policy depends on names only, so the endpoint (created first) can use
  # the workspace module's output without a cycle.
  s3_gateway_endpoint = {
    enabled = true
    policy  = module.workspace.s3_endpoint_policy
  }
}

module "nat" {
  source = "../../../nat-instance"

  name                    = "jwall-engineering-databricks-poc-nat"
  subnet_id               = module.network.public_subnet_ids[0]
  private_route_table_ids = local.nat_route_table_ids
  source_cidrs            = ["10.0.128.0/20", "10.0.144.0/20"]
  ami_id                  = "ami-0123456789abcdef0"
}

# ---------------------------------------------------------- workspace stack

module "catalog" {
  source = "../../../databricks-catalog"

  providers = {
    databricks = databricks.workspace
  }

  project          = "databricks-poc"
  workspace_id     = module.workspace.workspace_id
  admin_group_name = module.workspace.admin_group_name
  users_group_name = module.workspace.users_group_name

  apply_role_arn       = "arn:aws:iam::111122223333:role/jwall-engineering-databricks-poc-ci-apply"
  management_role_arns = ["arn:aws:iam::111122223333:role/admin"]

  tags = local.tags
}

module "workspace_config" {
  source = "../../../databricks-workspace-config"

  providers = {
    databricks = databricks.workspace
  }

  users_group_name = module.workspace.users_group_name
  metastore_id     = "abcdef01-2345-6789-abcd-ef0123456789"
  fixed_tags       = local.tags

  compute_policies = {
    team-a-jobs = {
      description = "Small autoscaling jobs compute"
      definition = {
        autotermination_minutes = { type = "fixed", value = 30, hidden = true }
        node_type_id            = { type = "allowlist", values = ["m5.xlarge"] }
        num_workers             = { type = "range", maxValue = 4 }
      }
    }
  }
}

# Child module resources are out of a test's reach, so the wiring is exposed
# through the modules' outputs and the fixture's own values.
output "private_route_table_id" {
  value = module.network.private_route_table_id
}

output "public_route_table_id" {
  value = module.network.route_table_id
}

output "s3_endpoint_id" {
  value = module.network.s3_endpoint_id
}

output "nat_route_table_ids" {
  value = local.nat_route_table_ids
}

output "endpoint_policy" {
  value = module.workspace.s3_endpoint_policy
}

output "catalog_bucket_name" {
  value = module.catalog.bucket_name
}

output "catalog_uc_role_arn" {
  value = module.catalog.uc_role_arn
}
