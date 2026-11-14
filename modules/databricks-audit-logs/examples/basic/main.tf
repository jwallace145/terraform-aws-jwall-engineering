module "context" {
  source = "../../../context"

  project     = "databricks-poc"
  environment = "prod"
  repository  = "example/infra"
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = module.context.tags
  }
}

# Account-level provider; authentication comes from the environment.
provider "databricks" {
  host = "https://accounts.cloud.databricks.com"
}

module "audit_logs" {
  source = "../../"

  account_id = "11111111-2222-3333-4444-555555555555"
}

output "bucket_arn" {
  value = module.audit_logs.bucket_arn
}
