# ci-policies is normally called by ci-plan-role, ci-preview-role and
# ci-apply-role. Calling it directly creates the policies without a role.
provider "aws" {
  region = "us-east-1"
}

module "ci_policies" {
  source = "../../"

  project           = "infra"
  role              = "plan"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"

  policies = ["tfstate/read", "foundation/read"]

  policy_inputs = {
    tfstate = {
      bucket_arn = "arn:aws:s3:::jwall-engineering-tfstate"
      key        = "project=infra/env=prod/infra-prod.tfstate"
    }
    foundation = {
      state_bucket_arn = "arn:aws:s3:::jwall-engineering-tfstate"
      hosted_zone_arn  = "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ"
    }
  }
}

output "arns" {
  value = module.ci_policies.arns
}
