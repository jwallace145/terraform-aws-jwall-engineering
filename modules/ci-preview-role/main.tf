locals {
  name = "${var.name_root}-${var.project}-ci-preview"
}

module "policies" {
  source = "../ci-policies"

  name_root         = var.name_root
  project           = var.project
  role              = "preview"
  oidc_provider_arn = var.oidc_provider_arn
  policies          = var.policies
  policy_inputs     = var.policy_inputs
}

module "role" {
  source = "../github-oidc-role"

  name                = local.name
  description         = "preview publishing for ${var.repository} pull requests"
  repository          = var.repository
  owner_id            = var.owner_id
  repository_id       = var.repository_id
  oidc_provider_arn   = var.oidc_provider_arn
  subjects            = ["pull_request"]
  trust_statement_sid = "GitHubPullRequests"
  component           = "ci"
  name_tag            = local.name

  managed_policies = module.policies.arns
}
