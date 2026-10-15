module "context" {
  source = "../../../context"

  project     = "infra"
  environment = "prod"
  repository  = "jwallace145/jwall-engineering-infra"
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = module.context.tags
  }
}

module "state_bucket" {
  source = "../../"

  name = "jwall-engineering-tfstate"
}

output "state_bucket_name" {
  value = module.state_bucket.name
}

output "state_bucket_arn" {
  value = module.state_bucket.arn
}
