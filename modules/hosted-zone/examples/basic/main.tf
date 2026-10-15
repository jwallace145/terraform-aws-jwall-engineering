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

module "zone" {
  source = "../../"

  name    = "jwall.engineering"
  comment = "jwall-engineering: zone owned by jwallace145/jwall-engineering-infra; records owned by project repos"

  # The four Amazon CAs ACM needs, plus Let's Encrypt for sites still served
  # by GitHub Pages.
  caa_issuers = ["amazon.com", "amazontrust.com", "awstrust.com", "amazonaws.com", "letsencrypt.org"]

  # Keep the Name tag the zone already carries.
  name_tag = "jwall-engineering-infra-dns-zone"
}

output "zone_id" {
  value = module.zone.zone_id
}

output "name_servers" {
  value = module.zone.name_servers
}
