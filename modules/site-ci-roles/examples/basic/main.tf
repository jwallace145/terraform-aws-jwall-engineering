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
  source = "../../../site-bucket"

  project = "guitar"
}

module "site_ci_roles" {
  source = "../../"

  project           = "guitar"
  repository        = "jwallace145/guitar"
  bucket_arn        = module.site_bucket.arn
  state_bucket_arn  = "arn:aws:s3:::jwall-engineering-terraform-state"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  zone_id           = "Z0123456789ABCDEFGHIJ"
  record_names = [
    "guitar.jwall.engineering",
    "dev.guitar.jwall.engineering",
    "*.preview.guitar.jwall.engineering",
  ]
}

output "plan_role_arn" {
  value = module.site_ci_roles.plan_role_arn
}

output "preview_role_arn" {
  value = module.site_ci_roles.preview_role_arn
}

output "apply_role_arn" {
  value = module.site_ci_roles.apply_role_arn
}
