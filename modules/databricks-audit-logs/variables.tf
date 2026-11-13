variable "account_id" {
  description = "Databricks account ID (a UUID). It is also the external ID the log delivery role requires from Databricks."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.account_id))
    error_message = "account_id must be the Databricks account ID, a UUID such as 11111111-2222-3333-4444-555555555555; change the account_id variable."
  }
}

variable "bucket_name" {
  description = "Name of the audit log bucket."
  type        = string
  default     = "jwall-engineering-databricks-audit-logs"

  validation {
    condition = (
      can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name)) &&
      !can(regex("\\.\\.", var.bucket_name))
    )
    error_message = "bucket_name must be a valid S3 bucket name: 3-63 characters of lowercase letters, digits, dots and hyphens, starting and ending with a letter or digit, without consecutive dots."
  }
}

variable "role_name" {
  description = "Name of the IAM role Databricks assumes to write the logs."
  type        = string
  default     = "jwall-engineering-databricks-log-delivery"

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.role_name))
    error_message = "role_name must be 1-64 characters of letters, digits and + = , . @ _ -; change the role_name variable."
  }
}

variable "prefix" {
  description = "Key prefix Databricks writes under. Databricks gets access to `<prefix>/*` only; other prefixes (for example `events/`) stay free for the account's own principals."
  type        = string
  default     = "audit"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.prefix))
    error_message = "prefix must be one path segment of letters, digits, dots, underscores and hyphens, without slashes (for example \"audit\"); change the prefix variable."
  }
}

variable "component" {
  description = "Value of the `Component` tag on the bucket and role."
  type        = string
  default     = "databricks-audit-logs"

  validation {
    condition     = length(var.component) > 0
    error_message = "component must not be empty."
  }
}
