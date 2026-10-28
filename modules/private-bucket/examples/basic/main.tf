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

module "records" {
  source = "../../"

  name = "jwall-engineering-rusty-chess-records"
}

output "arn" {
  value = module.records.arn
}
