module "context" {
  source = "../../../context"

  project     = "databricks-poc"
  environment = "prod"
  repository  = "example/infra"
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = module.context.tags
  }
}

module "network" {
  source = "../../../vpc"

  name                 = "team-a-databricks-poc"
  availability_zones   = ["us-east-1a"]
  private_subnet_cidrs = ["10.0.2.0/24"]
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
  source = "../../"

  name                    = "team-a-databricks-poc-nat"
  subnet_id               = module.network.public_subnet_ids[0]
  private_route_table_ids = [module.network.private_route_table_id]
  source_cidrs            = ["10.0.2.0/24"]
  ami_id                  = data.aws_ami.al2023_arm64.id
}

output "nat_public_ip" {
  value = module.nat.public_ip
}
