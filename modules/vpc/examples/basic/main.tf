module "context" {
  source = "../../../context"

  project     = "rusty-chess"
  environment = "prod"
  repository  = "jwallace145/rusty-chess-v2"
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = module.context.tags
  }
}

module "network" {
  source = "../../"

  name = "jwall-engineering-rusty-chess"
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}
