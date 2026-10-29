locals {
  name = "${var.name_root}-${var.project}-ci-task"
}

module "policies" {
  source = "../ci-policies"

  name_root         = var.name_root
  project           = var.project
  role              = "task"
  oidc_provider_arn = var.oidc_provider_arn
  policies          = var.policies
  policy_inputs     = var.policy_inputs
}

module "role" {
  source = "../github-oidc-role"

  name                = local.name
  description         = "remote CI tasks for ${var.repository} pull requests and branches"
  repository          = var.repository
  owner_id            = var.owner_id
  repository_id       = var.repository_id
  oidc_provider_arn   = var.oidc_provider_arn
  subjects            = var.subjects
  trust_statement_sid = "GitHubTaskEvents"
  component           = "ci"
  name_tag            = local.name

  managed_policies = module.policies.arns
}
