variable "name" {
  description = "Name of the managed policy, for example `jwall-engineering-rusty-chess-ci-apply-container-manage`."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,128}$", var.name))
    error_message = "name must be a valid IAM policy name: 1-128 characters from `A-Z a-z 0-9 + = , . @ _ -`."
  }
}

variable "name_root" {
  description = "Prefix of resource names, in kebab-case. Roles, policies, repositories and buckets are scoped to `<name_root>-<project>-*`; parameters and log groups to `/<name_root>/<project>/*`."
  type        = string
  default     = "jwall-engineering"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name_root))
    error_message = "name_root must be kebab-case: lowercase letters, digits and single hyphens."
  }
}

variable "project" {
  description = "Project name in kebab-case. Every resource ARN in the policy is built from `<name_root>-<project>`."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.project))
    error_message = "project must be kebab-case: lowercase letters, digits and single hyphens (e.g. `rusty-chess`)."
  }
}

variable "attachable_policy_arns" {
  description = "Extra managed policy ARNs the apply role may attach to `<name_root>-<project>-*` roles, on top of the project's own policies and `AmazonSSMManagedInstanceCore`."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.attachable_policy_arns : can(regex("^arn:aws:iam::(aws|[0-9]{12}):policy/[^*?]+$", a))])
    error_message = "every attachable policy must be an exact managed policy ARN without wildcards."
  }
}
