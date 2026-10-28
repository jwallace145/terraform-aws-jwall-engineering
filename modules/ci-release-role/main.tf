locals {
  name = "${var.name_root}-${var.project}-ci-release"
}

module "policies" {
  source = "../ci-policies"

  name_root         = var.name_root
  project           = var.project
  role              = "release"
  oidc_provider_arn = var.oidc_provider_arn
  policies          = var.policies
  policy_inputs     = var.policy_inputs
}

module "role" {
  source = "../github-oidc-role"

  name                = local.name
  description         = "container release for ${var.repository} release tags (${var.tag_pattern})"
  repository          = var.repository
  owner_id            = var.owner_id
  repository_id       = var.repository_id
  oidc_provider_arn   = var.oidc_provider_arn
  subjects            = ["ref:refs/tags/${var.tag_pattern}"]
  trust_statement_sid = "GitHubReleaseTags"
  component           = "ci"
  name_tag            = local.name

  managed_policies = module.policies.arns
}
