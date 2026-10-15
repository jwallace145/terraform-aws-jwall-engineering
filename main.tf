# Root module: the full static-site stack a project repository deploys.
#
#   prod     https://<domain_name>              <- <bucket>/prod
#   dev      https://<dev_domain_name>          <- <bucket>/dev      (optional)
#   preview  https://pr-<n>.preview.<domain>    <- <bucket>/previews/pr-<n>
#
# The bucket and CI roles are created by the infra repo with the
# `site-bucket` and `ci-*-role` submodules; this module only consumes the
# bucket. Every submodule can also be used on its own.

module "prod" {
  source = "./modules/static-site"

  bucket_name                 = var.bucket_name
  bucket_regional_domain_name = var.bucket_regional_domain_name
  origin_path                 = "/prod"
  domain_name                 = var.domain_name
  zone_id                     = var.zone_id
}

module "dev" {
  source = "./modules/static-site"
  count  = var.dev_domain_name == null ? 0 : 1

  bucket_name                 = var.bucket_name
  bucket_regional_domain_name = var.bucket_regional_domain_name
  origin_path                 = "/dev"
  domain_name                 = var.dev_domain_name
  zone_id                     = var.zone_id
}

module "preview" {
  source = "./modules/preview-site"
  count  = var.enable_preview ? 1 : 0

  bucket_name                 = var.bucket_name
  bucket_regional_domain_name = var.bucket_regional_domain_name
  site_domain                 = var.domain_name
  zone_id                     = var.zone_id
}
