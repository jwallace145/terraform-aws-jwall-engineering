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

module "ci_preview" {
  source = "../../"

  project           = "guitar"
  repository        = "jwallace145/guitar"
  owner_id          = "35950238"  # gh api users/jwallace145 --jq .id
  repository_id     = "123456789" # gh api repos/jwallace145/guitar --jq .id
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"

  policies = ["static-site/previews"]

  policy_inputs = {
    static_site = {
      bucket_arn = module.site_bucket.arn
    }
  }
}

output "role_arn" {
  value = module.ci_preview.role_arn
}
