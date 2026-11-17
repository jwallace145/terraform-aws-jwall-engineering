variable "name_root" {
  description = "Prefix of every resource name, in kebab-case: `name_prefix` is `<name_root>-<project>-<environment>` and `bucket_name` is `<name_root>-<project>`. Independent of the `organization` tag value."
  type        = string
  default     = "jwall-engineering"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name_root))
    error_message = "name_root must be kebab-case: lowercase letters, digits and single hyphens."
  }
}

variable "managed_by" {
  description = "Value of the `ManagedBy` tag: the tool that manages the project's resources."
  type        = string
  default     = "jwall-engineering-infra"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.managed_by))
    error_message = "managed_by must be kebab-case: lowercase letters, digits and single hyphens."
  }
}

variable "project" {
  description = "Project name in kebab-case, for example `guitar`. Used in resource names and the `Project` tag."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.project))
    error_message = "project must be kebab-case: lowercase letters, digits and single hyphens (e.g. `my-site`)."
  }

  validation {
    condition     = length(var.project) <= 30
    error_message = "project must be at most 30 characters so derived resource names fit AWS limits."
  }
}

variable "environment" {
  description = "Deployment environment. One of `dev`, `staging`, `prod` or `preview`."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod", "preview"], var.environment)
    error_message = "environment must be one of: dev, staging, prod, preview."
  }
}

variable "repository" {
  description = "GitHub repository that owns the project, as `owner/repo` (for example `jwallace145/guitar`)."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?/[A-Za-z0-9._-]+$", var.repository))
    error_message = "repository must be an `owner/repo` string (e.g. `jwallace145/guitar`)."
  }
}

variable "owner" {
  description = "GitHub user responsible for the project. Becomes the `Owner` tag."
  type        = string
  default     = "jwallace145"

  validation {
    condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$", var.owner))
    error_message = "owner must be a GitHub username: alphanumerics and single hyphens, not starting or ending with a hyphen."
  }
}

variable "organization" {
  description = "Organization the project belongs to. Becomes the `Organization` tag."
  type        = string
  default     = "jwall-engineering"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.organization))
    error_message = "organization must be kebab-case: lowercase letters, digits and single hyphens."
  }
}

variable "extra_tags" {
  description = "Additional tags merged into `tags`. The required keys (Organization, Project, Environment, Repository, ManagedBy, Owner) always win on conflict."
  type        = map(string)
  default     = {}
}
