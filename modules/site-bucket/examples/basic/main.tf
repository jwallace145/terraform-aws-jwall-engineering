module "context" {
  source = "../../../context"

  project     = "guitar"
  environment = "prod"
  repository  = "jwallace145/guitar"
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = module.context.tags
  }
}

module "site_bucket" {
  source = "../../"

  project = "guitar"
}

output "bucket_name" {
  value = module.site_bucket.name
}

output "bucket_arn" {
  value = module.site_bucket.arn
}

output "bucket_regional_domain_name" {
  value = module.site_bucket.regional_domain_name
}
