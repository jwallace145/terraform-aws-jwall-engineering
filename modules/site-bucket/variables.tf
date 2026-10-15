variable "project" {
  description = "Project name in kebab-case. The bucket is named `jwall-engineering-<project>`."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.project))
    error_message = "project must be kebab-case: lowercase letters, digits and single hyphens (e.g. `my-site`)."
  }

  validation {
    condition     = length(var.project) <= 30
    error_message = "project must be at most 30 characters so the bucket name stays within S3's 63-character limit."
  }
}
