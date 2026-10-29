module "context" {
  source = "../../../context"

  project     = "rusty-chess"
  environment = "prod"
  repository  = "jwallace145/rusty-chess-v2"
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = module.context.tags
  }
}

module "vpc" {
  source = "../../../vpc"

  name       = "jwall-engineering-rusty-chess"
  cidr_block = "10.40.0.0/16"
}

# The caller owns the results bucket the task instances write to.
module "task_results" {
  source = "../../../private-bucket"

  name                           = "jwall-engineering-rusty-chess-tasks"
  current_object_expiration_days = 7
}

module "tasks" {
  source = "../../"

  project            = "rusty-chess"
  vpc_id             = module.vpc.vpc_id
  rust_toolchain     = "1.91.0"
  max_lifetime_hours = 6
}

output "launch_template_name" {
  value = module.tasks.launch_template_name
}
