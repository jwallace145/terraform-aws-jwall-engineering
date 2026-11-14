# The account stack: network, NAT and workspace. Its outputs feed the
# workspace stack, applied afterwards with a workspace-level provider.
module "context" {
  source = "../../../context"

  project     = "databricks-poc"
  environment = "dev"
  repository  = "example/infra"

  extra_tags = {
    CostCenter = "cc-0000"
    Workspace  = "databricks-poc-dev"
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = module.context.tags
  }
}

# Account-level provider; authentication and the account ID come from the
# environment (DATABRICKS_CLIENT_ID, DATABRICKS_CLIENT_SECRET,
# DATABRICKS_ACCOUNT_ID).
provider "databricks" {
  host = "https://accounts.cloud.databricks.com"
}

module "network" {
  source = "../../../vpc"

  name                 = "jwall-engineering-databricks-poc"
  availability_zones   = ["us-east-1a", "us-east-1b"]
  private_subnet_cidrs = ["10.0.128.0/20", "10.0.144.0/20"]
  s3_gateway_endpoint  = { enabled = true }
}

# Pinned AL2023 arm64 image, so a new release does not replace the NAT.
data "aws_ami" "al2023_arm64" {
  owners      = ["amazon"]
  most_recent = false
  filter {
    name   = "name"
    values = ["al2023-ami-2023.6.20250115.0-kernel-6.1-arm64"]
  }
}

module "nat" {
  source = "../../../nat-instance"

  name                    = "jwall-engineering-databricks-poc-nat"
  subnet_id               = module.network.public_subnet_ids[0]
  private_route_table_ids = [module.network.private_route_table_id]
  source_cidrs            = ["10.0.128.0/20", "10.0.144.0/20"]
  ami_id                  = data.aws_ami.al2023_arm64.id
}

module "workspace" {
  source = "../../"

  account_id   = "11111111-2222-3333-4444-555555555555"
  project      = "databricks-poc"
  environment  = "dev"
  vpc_id       = module.network.vpc_id
  subnet_ids   = module.network.private_subnet_ids
  metastore_id = "abcdef01-2345-6789-abcd-ef0123456789"
  tags         = module.context.tags

  admin_user_names                 = ["owner@example.com"]
  user_names                       = ["analyst@example.com"]
  service_principal_application_id = "00000000-0000-0000-0000-000000000000"
}

# The workspace stack's provider: host = this output.
output "workspace_url" {
  value = module.workspace.workspace_url
}
