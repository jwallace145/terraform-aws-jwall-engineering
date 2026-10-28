variable "name_root" {
  description = "Prefix of the role and policy names, in kebab-case. The role is named `<name_root>-<project>-ci-release`."
  type        = string
  default     = "jwall-engineering"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name_root))
    error_message = "name_root must be kebab-case: lowercase letters, digits and single hyphens."
  }
}

variable "project" {
  description = "Project in kebab-case, for example `rusty-chess`. The role is named `<name_root>-<project>-ci-release`, and `container/release` is scoped to the project's repository, `/<name_root>/<project>/bot/*` parameters and instances tagged `Project = <project>`."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.project))
    error_message = "project must be kebab-case: lowercase letters, digits and single hyphens (e.g. `my-site`)."
  }

  validation {
    condition     = length("${var.name_root}-${var.project}-ci-release") <= 64
    error_message = "name_root and project are too long: `<name_root>-<project>-ci-release` must fit IAM's 64-character role name limit."
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
  description = "Managed policies to create and attach, by catalog name. This role accepts only release and common policies: `container/release`, `ecr/pull`."
  type        = set(string)

  # Mirrors the catalog's allow-list so the error names this module.
  validation {
    condition     = length(var.policies) > 0 && alltrue([for p in var.policies : contains(["container/release", "ecr/pull"], p)])
    error_message = "ci-release-role accepts only release and common policies: container/release, ecr/pull."
  }
}

variable "policy_inputs" {
  description = "Values the requested policies are built from, one optional section per policy family. `container/release` needs none; `ecr/pull` needs `ecr = { repository_arn }`. The `ci-policies` module checks the shape."
  # `any`: the catalog module owns the type, so adding a policy family does not
  # touch the role modules.
  type    = any
  default = {}
}

variable "tag_pattern" {
  description = "Git tags whose workflows may assume the role, as a glob. The role trusts `ref:refs/tags/<tag_pattern>`; the default `v*` matches Release Please tags like `v1.2.3`."
  type        = string
  default     = "v*"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]*\\*?$", var.tag_pattern)) && length(var.tag_pattern) > 0
    error_message = "tag_pattern must be letters, digits, `.`, `_` and `-`, optionally ending in one `*` (for example `v*`)."
  }
}
