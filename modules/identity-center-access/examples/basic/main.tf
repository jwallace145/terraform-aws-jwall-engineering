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

data "aws_caller_identity" "current" {}

# The organization instance, enabled once in the console.
data "aws_ssoadmin_instances" "this" {}

module "owner_admin" {
  source = "../../"

  instance_arn      = one(data.aws_ssoadmin_instances.this.arns)
  identity_store_id = one(data.aws_ssoadmin_instances.this.identity_store_ids)
  account_id        = data.aws_caller_identity.current.account_id

  user = {
    user_name   = "jwallace145"
    given_name  = "Jane"
    family_name = "Doe"
    email       = "owner@example.com"
  }
}

output "role_arn" {
  value = module.owner_admin.role_arn
}
