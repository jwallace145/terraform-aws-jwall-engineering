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

module "nnue" {
  source = "../../"

  name              = "jwall-engineering-rusty-chess-nnue"
  prefix            = "data/"
  writer_role_names = ["jwall-engineering-rusty-chess-task"]
}

output "uri" {
  value = module.nnue.uri
}
