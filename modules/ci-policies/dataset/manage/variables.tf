variable "name" {
  description = "Name of the managed policy, for example `jwall-engineering-rusty-chess-ci-apply-dataset-manage`."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,128}$", var.name))
    error_message = "name must be a valid IAM policy name: 1-128 characters from `A-Z a-z 0-9 + = , . @ _ -`."
  }
}

variable "name_root" {
  description = "Prefix of resource names, in kebab-case. Dataset buckets must be named `<name_root>-<project>-*`."
  type        = string
  default     = "jwall-engineering"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name_root))
    error_message = "name_root must be kebab-case: lowercase letters, digits and single hyphens."
  }
}

variable "project" {
  description = "Project name in kebab-case."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.project))
    error_message = "project must be kebab-case: lowercase letters, digits and single hyphens (e.g. `rusty-chess`)."
  }
}

variable "bucket_names" {
  description = "The project's dataset buckets, each named `<name_root>-<project>-<dataset>`."
  type        = list(string)

  validation {
    condition     = length(var.bucket_names) > 0 && alltrue([for b in var.bucket_names : startswith(b, "${var.name_root}-${var.project}-")])
    error_message = "bucket_names must list at least one bucket, each named <name_root>-<project>-<dataset>."
  }
}
