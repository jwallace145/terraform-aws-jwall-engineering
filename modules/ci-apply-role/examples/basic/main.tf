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

module "ci_apply" {
  source = "../../"

  project           = "guitar"
  repository        = "jwallace145/guitar"
  owner_id          = "35950238"  # gh api users/jwallace145 --jq .id
  repository_id     = "123456789" # gh api repos/jwallace145/guitar --jq .id
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  environment       = "prod"

  policies = ["tfstate/write", "static-site/read", "static-site/deploy"]

  policy_inputs = {
    tfstate = {
      bucket_arn = "arn:aws:s3:::jwall-engineering-tfstate"
      prefix     = "project=guitar/"
    }
    static_site = {
      bucket_arn = module.site_bucket.arn
      zone_id    = "Z0123456789ABCDEFGHIJ"
      record_names = [
        "guitar.jwall.engineering",
        "dev.guitar.jwall.engineering",
        "*.preview.guitar.jwall.engineering",
      ]
    }
  }
}

output "role_arn" {
  value = module.ci_apply.role_arn
}

output "policy_arns" {
  value = module.ci_apply.policy_arns
}
