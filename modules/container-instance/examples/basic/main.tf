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

module "image" {
  source = "../../../ecr-repository"

  name = "jwall-engineering-rusty-chess"
}

module "network" {
  source = "../../../vpc"

  name = "jwall-engineering-rusty-chess"
}

module "records" {
  source = "../../../private-bucket"

  name = "jwall-engineering-rusty-chess-records"
}

module "bot" {
  source = "../../"

  name                 = "jwall-engineering-rusty-chess-bot"
  project              = "rusty-chess"
  image_repository_url = module.image.url
  image_repository_arn = module.image.arn
  vpc_id               = module.network.vpc_id
  subnet_id            = module.network.public_subnet_ids[0]

  secret_parameters = {
    LICHESS_TOKEN = "/jwall-engineering/rusty-chess/lichess-token"
  }
  container_environment = {
    ENGINE_HASH_MB          = "128"
    ENGINE_MOVE_OVERHEAD_MS = "500"
  }
  bot_name = "rusty-chess-bot"

  records_bucket_name    = module.records.name
  records_container_path = "/opt/lichess-bot/game_records"
  health_log_pattern     = "awaiting challenges"
}

output "instance_id" {
  value = module.bot.instance_id
}

output "parameter_names" {
  value = module.bot.parameter_names
}
