variable "name_root" {
  description = "Prefix of the role and policy names, in kebab-case. The role is named `<name_root>-<project>-ci-apply`."
  type        = string
  default     = "jwall-engineering"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name_root))
    error_message = "name_root must be kebab-case: lowercase letters, digits and single hyphens."
  }
}

variable "project" {
  description = "Project in kebab-case, for example `guitar` or `infra`. The role is named `<name_root>-<project>-ci-apply`, and static-site policies are scoped to resources tagged `Project = <project>`."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.project))
    error_message = "project must be kebab-case: lowercase letters, digits and single hyphens (e.g. `my-site`)."
  }

  validation {
    condition     = length("${var.name_root}-${var.project}-ci-apply") <= 64
    error_message = "name_root and project are too long: `<name_root>-<project>-ci-apply` must fit IAM's 64-character role name limit."
  }
}

variable "repository" {
  description = "GitHub repository whose workflows may assume the role, as `owner/repo`."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?/[A-Za-z0-9._-]+$", var.repository))
    error_message = "repository must be an `owner/repo` string (e.g. `jwallace145/guitar`)."
  }
}

variable "owner_id" {
  description = "Numeric GitHub ID of the repository owner (`gh api users/<owner> --jq .id`). When set together with `repository_id`, the role also trusts GitHub's immutable subject form `repo:<owner>@<owner_id>/<name>@<repository_id>:...`."
  type        = string
  default     = null
}

variable "repository_id" {
  description = "Numeric GitHub ID of the repository (`gh api repos/<owner>/<repo> --jq .id`). When set together with `owner_id`, the role also trusts GitHub's immutable subject form."
  type        = string
  default     = null
}

variable "oidc_provider_arn" {
  description = "ARN of the account's GitHub Actions OIDC provider (`token.actions.githubusercontent.com`)."
  type        = string
}

variable "policies" {
  description = "Managed policies to create and attach, by catalog name. This role accepts only read, write and common policies: `tfstate/read`, `tfstate/write`, `static-site/read`, `static-site/deploy`, `foundation/read`, `foundation/manage`, `ecr/pull`, `ecr/push`."
  type        = set(string)
}

variable "policy_inputs" {
  description = "Values the requested policies are built from, one optional section per policy family: `tfstate = { bucket_arn, key or prefix }`, `static_site = { bucket_arn, zone_id?, record_names? }`, `foundation = { state_bucket_arn, hosted_zone_arn, managed_bucket_patterns?, attachable_policy_arns? }`. Only the sections the requested policies need are required. The `ci-policies` module checks the shape."
  # `any`: the catalog module owns the type, so adding a policy family does not
  # touch the role modules.
  type    = any
  default = {}
}

variable "environment" {
  description = "GitHub environment whose jobs may assume the role. The role trusts `environment:<environment>`."
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]*$", var.environment))
    error_message = "environment must be a GitHub environment name of letters, digits, `_` and `-`."
  }
}
