module "context" {
  source = "../../"

  project     = "guitar"
  environment = "prod"
  repository  = "jwallace145/guitar"

  extra_tags = {
    CostCenter = "personal"
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = module.context.tags
  }
}

output "tags" {
  value = module.context.tags
}

output "name_prefix" {
  value = module.context.name_prefix
}

output "bucket_name" {
  value = module.context.bucket_name
}
