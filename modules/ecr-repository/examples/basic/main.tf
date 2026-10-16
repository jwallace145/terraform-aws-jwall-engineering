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

module "sites_image" {
  source = "../../"

  name                       = "jwall-engineering-sites"
  keep_release_images        = 20
  expire_untagged_after_days = 7
}

output "url" {
  value = module.sites_image.url
}
