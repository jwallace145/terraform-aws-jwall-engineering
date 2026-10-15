module "context" {
  source = "../../../context"

  project     = "guitar"
  environment = "preview"
  repository  = "jwallace145/guitar"
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = module.context.tags
  }
}

module "preview_site" {
  source = "../../"

  bucket_name                 = module.context.bucket_name
  bucket_regional_domain_name = "${module.context.bucket_name}.s3.us-east-1.amazonaws.com"
  site_domain                 = "guitar.jwall.engineering"
  zone_id                     = "Z0123456789ABCDEFGHIJ"
}

output "distribution_id" {
  value = module.preview_site.distribution_id
}

output "url_pattern" {
  value = module.preview_site.url_pattern
}
