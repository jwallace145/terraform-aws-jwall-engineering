module "context" {
  source = "../../modules/context"

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

module "site" {
  source = "../../"

  bucket_name                 = module.context.bucket_name
  bucket_regional_domain_name = "${module.context.bucket_name}.s3.us-east-1.amazonaws.com"
  domain_name                 = "guitar.jwall.engineering"
  dev_domain_name             = "dev.guitar.jwall.engineering"
  zone_id                     = "Z0123456789ABCDEFGHIJ"
}

output "urls" {
  value = {
    prod    = module.site.prod_url
    dev     = module.site.dev_url
    preview = module.site.preview_url_pattern
  }
}

output "distribution_ids" {
  value = module.site.distribution_ids
}
