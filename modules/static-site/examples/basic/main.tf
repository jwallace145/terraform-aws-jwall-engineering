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

module "static_site" {
  source = "../../"

  bucket_name                 = module.context.bucket_name
  bucket_regional_domain_name = "${module.context.bucket_name}.s3.us-east-1.amazonaws.com"
  origin_path                 = "/prod"
  domain_name                 = "guitar.jwall.engineering"
  zone_id                     = "Z0123456789ABCDEFGHIJ"
}

output "distribution_id" {
  value = module.static_site.distribution_id
}

output "distribution_arn" {
  value = module.static_site.distribution_arn
}

output "url" {
  value = module.static_site.url
}
