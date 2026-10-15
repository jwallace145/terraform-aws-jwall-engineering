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
  source = "../../../tfstate-bucket"

  name = "jwall-engineering-tfstate"
}

module "zone" {
  source = "../../../hosted-zone"

  name    = "jwall.engineering"
  comment = "jwall-engineering: zone owned by jwallace145/jwall-engineering-infra; records owned by project repos"
}

module "infra_ci_roles" {
  source = "../../"

  repository        = "jwallace145/jwall-engineering-infra"
  owner_id          = "35950238"   # gh api users/jwallace145 --jq .id
  repository_id     = "1420037633" # gh api repos/jwallace145/jwall-engineering-infra --jq .id
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  state_bucket_arn  = module.state_bucket.arn
  state_key         = "project=infra/env=prod/infra-prod.tfstate"
  hosted_zone_arn   = module.zone.arn
}

output "plan_role_arn" {
  value = module.infra_ci_roles.plan_role_arn
}

output "apply_role_arn" {
  value = module.infra_ci_roles.apply_role_arn
}
