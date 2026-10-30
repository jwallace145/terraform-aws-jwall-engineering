variable "name" {
  description = "Name of the managed policy, for example `jwall-engineering-rusty-chess-ci-task-task-launch`."
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

variable "instance_types" {
  description = "Instance types the role may launch, for example `[\"c8a.xlarge\", \"c8a.2xlarge\"]`."
  type        = list(string)

  validation {
    condition     = length(var.instance_types) > 0 && alltrue([for t in var.instance_types : can(regex("^[a-z0-9]+\\.[a-z0-9]+$", t))])
    error_message = "instance_types must list at least one instance type like c8a.xlarge."
  }
}

variable "profiles" {
  description = "The project's task profiles (`task-runner` module instances). The role may pass each one's instance role: `<name_root>-<project>-task` for `cpu`, `<name_root>-<project>-task-<profile>` for the others."
  type        = list(string)
  default     = ["cpu"]

  validation {
    condition     = length(var.profiles) > 0 && alltrue([for p in var.profiles : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", p))])
    error_message = "profiles must list at least one kebab-case profile, e.g. [\"cpu\", \"gpu\"]."
  }
}
