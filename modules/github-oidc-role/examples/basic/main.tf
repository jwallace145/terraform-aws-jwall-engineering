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

# A read-only plan role for pull requests, trusted in both subject forms.
module "plan_role" {
  source = "../../"

  name              = "jwall-engineering-infra-ci-plan"
  description       = "terraform plan for jwallace145/jwall-engineering-infra pull requests (read-only)"
  repository        = "jwallace145/jwall-engineering-infra"
  owner_id          = "35950238"   # gh api users/jwallace145 --jq .id
  repository_id     = "1420037633" # gh api repos/jwallace145/jwall-engineering-infra --jq .id
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  subjects          = ["pull_request"]
  component         = "ci"

  managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]

  inline_policies = {
    state = {
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "ReadOwnState"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:GetObjectVersion"]
          Resource = "arn:aws:s3:::jwall-engineering-tfstate/project=infra/env=prod/infra-prod.tfstate"
        },
      ]
    }
  }
}

output "plan_role_arn" {
  value = module.plan_role.arn
}
