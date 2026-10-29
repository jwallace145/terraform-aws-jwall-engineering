variable "name_root" {
  description = "Prefix of the role and policy names, in kebab-case. The role is named `<name_root>-<project>-ci-task`."
  type        = string
  default     = "jwall-engineering"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name_root))
    error_message = "name_root must be kebab-case: lowercase letters, digits and single hyphens."
  }
}

variable "project" {
  description = "Project in kebab-case, for example `rusty-chess`. The role is named `<name_root>-<project>-ci-task`, and `task/launch` is scoped to the project's launch templates, network, task role and instances tagged `Project = <project>` and `Purpose = ci-task`."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.project))
    error_message = "project must be kebab-case: lowercase letters, digits and single hyphens (e.g. `my-site`)."
  }

  validation {
    condition     = length("${var.name_root}-${var.project}-ci-task") <= 64
    error_message = "name_root and project are too long: `<name_root>-<project>-ci-task` must fit IAM's 64-character role name limit."
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
  description = "Managed policies to create and attach, by catalog name. This role accepts only task and common policies: `task/launch`, `ecr/pull`."
  type        = set(string)

  # Mirrors the catalog's allow-list so the error names this module.
  validation {
    condition     = length(var.policies) > 0 && alltrue([for p in var.policies : contains(["task/launch", "ecr/pull"], p)])
    error_message = "ci-task-role accepts only task and common policies: task/launch, ecr/pull."
  }
}

variable "policy_inputs" {
  description = "Values the requested policies are built from, one optional section per policy family. `task/launch` needs `task = { instance_types }`; `ecr/pull` needs `ecr = { repository_arn }`. The `ci-policies` module checks the shape."
  # `any`: the catalog module owns the type, so adding a policy family does not
  # touch the role modules.
  type    = any
  default = {}
}

variable "subjects" {
  description = "GitHub OIDC subjects, after `repo:<repository>:`, whose workflows may assume the role. The default trusts the repository's pull requests and its `main` branch. GitHub issues no OIDC token to pull request runs from forks, so `pull_request` admits same-repository pull requests only. Each subject is exact: `pull_request` or `ref:refs/heads/<branch>`, with no wildcards."
  type        = list(string)
  default     = ["pull_request", "ref:refs/heads/main"]

  validation {
    condition = length(var.subjects) > 0 && alltrue([
      for s in var.subjects : s == "pull_request" || can(regex("^ref:refs/heads/[A-Za-z0-9._/-]+$", s))
    ])
    error_message = "subjects must each be `pull_request` or `ref:refs/heads/<branch>` with no wildcards; tags and environments are not trusted."
  }
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds. `task run` holds one session for the whole task, so it must outlast the project's longest task (task-runner.max_hours) plus launch and setup. The default, 7 hours, covers the default 6-hour cap; raise it, to at most 12 hours, for longer tasks."
  type        = number
  default     = 25200

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds (IAM's limits)."
  }
}
