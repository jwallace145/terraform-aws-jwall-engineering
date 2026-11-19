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

# EC2 needs this role before the first Spot launch in an account, and creates
# it on that launch only if the caller may create service-linked roles. A task
# launch role should not be able to, so the account's foundation stack creates
# it instead.
module "spot_role" {
  source = "../../"

  aws_service_name = "spot.amazonaws.com"
  description      = "Default EC2 Spot Service Linked Role"
}

# An account that already has the role (EC2 created it on an earlier Spot
# launch) adopts it rather than creating a second one, which IAM refuses:
#
# import {
#   to = module.spot_role.aws_iam_service_linked_role.this
#   id = "arn:aws:iam::123456789012:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot"
# }

output "arn" {
  value = module.spot_role.arn
}
