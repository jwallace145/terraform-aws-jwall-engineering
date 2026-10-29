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

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

module "rusty_chess_task" {
  source = "../../"

  project           = "rusty-chess"
  repository        = "jwallace145/rusty-chess-v2"
  oidc_provider_arn = data.aws_iam_openid_connect_provider.github.arn

  policies = ["task/launch"]
  policy_inputs = {
    task = { instance_types = ["c8a.xlarge", "c8a.2xlarge"] }
  }
}

output "role_arn" {
  value = module.rusty_chess_task.role_arn
}
