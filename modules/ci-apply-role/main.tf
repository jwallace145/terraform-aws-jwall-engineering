locals {
  name = "${var.name_root}-${var.project}-ci-apply"

  # GitHubProdEnvironment for `prod`, GitHubStagingEuEnvironment for `staging-eu`.
  apply_trust_sid = "GitHub${join("", [for w in split(" ", replace(replace(var.environment, "-", " "), "_", " ")) : title(w)])}Environment"
}

module "policies" {
  source = "../ci-policies"

  name_root         = var.name_root
  project           = var.project
  role              = "apply"
  oidc_provider_arn = var.oidc_provider_arn
  policies          = var.policies
  policy_inputs     = var.policy_inputs
}

module "role" {
  source = "../github-oidc-role"

  name                = local.name
  description         = "terraform apply for ${var.repository} releases (${var.environment} environment)"
  repository          = var.repository
  owner_id            = var.owner_id
  repository_id       = var.repository_id
  oidc_provider_arn   = var.oidc_provider_arn
  subjects            = ["environment:${var.environment}"]
  trust_statement_sid = local.apply_trust_sid
  component           = "ci"
  name_tag            = local.name

  managed_policies = module.policies.arns
}
