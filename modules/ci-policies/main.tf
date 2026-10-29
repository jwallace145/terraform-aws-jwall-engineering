locals {
  # Every supported policy and its class. This is the only list of policy
  # names: a role's allow-list is the policies whose class it accepts. Adding
  # a policy means a folder under <family>/<name>, an entry here and a module
  # block below.
  catalog = {
    "tfstate/read"         = "read"
    "tfstate/write"        = "write"
    "static-site/read"     = "read"
    "static-site/deploy"   = "write"
    "static-site/previews" = "preview"
    "foundation/read"      = "read"
    "foundation/manage"    = "write"
    "ecr/pull"             = "common"
    "ecr/push"             = "write"
    "container/read"       = "read"
    "container/manage"     = "write"
    "container/release"    = "release"
    "task/read"            = "read"
    "task/manage"          = "write"
    "task/launch"          = "task"
  }

  # plan and preview trust `pull_request`, so unreviewed code can assume them.
  # Only the apply role, behind a GitHub environment, may write. `common`
  # policies are ones every role needs to run at all, such as pulling the CI
  # tool image; they grant nothing a pull request could misuse.
  #
  # release trusts a consumer repository's release tags: it may ship an image
  # and roll it out (`container/release`), nothing that reads or changes the
  # stack.
  allowed_classes = {
    plan    = ["read", "common"]
    preview = ["preview", "common"]
    apply   = ["read", "write", "common"]
    release = ["release", "common"]
    task    = ["task", "common"]
  }

  # <name_root>-<project>-ci-<role>-<family>-<name>
  name_prefix = "${var.name_root}-${var.project}-ci-${var.role}"
  names       = { for p in keys(local.catalog) : p => "${local.name_prefix}-${replace(p, "/", "-")}" }

  tfstate     = var.policy_inputs.tfstate
  static_site = var.policy_inputs.static_site
  foundation  = var.policy_inputs.foundation
  ecr         = var.policy_inputs.ecr
  container   = var.policy_inputs.container
  task        = var.policy_inputs.task
}

module "tfstate_read" {
  source = "./tfstate/read"
  count  = contains(var.policies, "tfstate/read") ? 1 : 0

  name       = local.names["tfstate/read"]
  bucket_arn = local.tfstate.bucket_arn
  key        = local.tfstate.key
  prefix     = local.tfstate.prefix
}

module "tfstate_write" {
  source = "./tfstate/write"
  count  = contains(var.policies, "tfstate/write") ? 1 : 0

  name       = local.names["tfstate/write"]
  bucket_arn = local.tfstate.bucket_arn
  key        = local.tfstate.key
  prefix     = local.tfstate.prefix
}

module "static_site_read" {
  source = "./static-site/read"
  count  = contains(var.policies, "static-site/read") ? 1 : 0

  name       = local.names["static-site/read"]
  name_root  = var.name_root
  project    = var.project
  bucket_arn = local.static_site.bucket_arn
  zone_id    = local.static_site.zone_id
}

module "static_site_deploy" {
  source = "./static-site/deploy"
  count  = contains(var.policies, "static-site/deploy") ? 1 : 0

  name         = local.names["static-site/deploy"]
  name_root    = var.name_root
  project      = var.project
  bucket_arn   = local.static_site.bucket_arn
  zone_id      = local.static_site.zone_id
  record_names = local.static_site.record_names
}

module "static_site_previews" {
  source = "./static-site/previews"
  count  = contains(var.policies, "static-site/previews") ? 1 : 0

  name       = local.names["static-site/previews"]
  bucket_arn = local.static_site.bucket_arn
}

module "foundation_read" {
  source = "./foundation/read"
  count  = contains(var.policies, "foundation/read") ? 1 : 0

  name                    = local.names["foundation/read"]
  name_root               = var.name_root
  state_bucket_arn        = local.foundation.state_bucket_arn
  hosted_zone_arn         = local.foundation.hosted_zone_arn
  managed_bucket_patterns = local.foundation.managed_bucket_patterns
  oidc_provider_arn       = var.oidc_provider_arn
}

module "foundation_manage" {
  source = "./foundation/manage"
  count  = contains(var.policies, "foundation/manage") ? 1 : 0

  name                    = local.names["foundation/manage"]
  name_root               = var.name_root
  state_bucket_arn        = local.foundation.state_bucket_arn
  hosted_zone_arn         = local.foundation.hosted_zone_arn
  managed_bucket_patterns = local.foundation.managed_bucket_patterns
  attachable_policy_arns  = local.foundation.attachable_policy_arns
}

module "ecr_pull" {
  source = "./ecr/pull"
  count  = contains(var.policies, "ecr/pull") ? 1 : 0

  name           = local.names["ecr/pull"]
  repository_arn = local.ecr.repository_arn
}

module "ecr_push" {
  source = "./ecr/push"
  count  = contains(var.policies, "ecr/push") ? 1 : 0

  name           = local.names["ecr/push"]
  repository_arn = local.ecr.repository_arn
}

module "container_read" {
  source = "./container/read"
  count  = contains(var.policies, "container/read") ? 1 : 0

  name      = local.names["container/read"]
  name_root = var.name_root
  project   = var.project
}

module "container_manage" {
  source = "./container/manage"
  count  = contains(var.policies, "container/manage") ? 1 : 0

  name                   = local.names["container/manage"]
  name_root              = var.name_root
  project                = var.project
  attachable_policy_arns = try(local.container.attachable_policy_arns, null) == null ? [] : local.container.attachable_policy_arns
}

module "container_release" {
  source = "./container/release"
  count  = contains(var.policies, "container/release") ? 1 : 0

  name      = local.names["container/release"]
  name_root = var.name_root
  project   = var.project
}

module "task_read" {
  source = "./task/read"
  count  = contains(var.policies, "task/read") ? 1 : 0

  name      = local.names["task/read"]
  name_root = var.name_root
  project   = var.project
}

module "task_manage" {
  source = "./task/manage"
  count  = contains(var.policies, "task/manage") ? 1 : 0

  name      = local.names["task/manage"]
  name_root = var.name_root
  project   = var.project
}

module "task_launch" {
  source = "./task/launch"
  count  = contains(var.policies, "task/launch") ? 1 : 0

  name           = local.names["task/launch"]
  name_root      = var.name_root
  project        = var.project
  instance_types = try(local.task.instance_types, [])
}
