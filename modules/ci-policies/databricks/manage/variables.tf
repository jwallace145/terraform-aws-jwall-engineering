variable "name" {
  description = "Name of the managed policy, for example `jwall-engineering-databricks-poc-ci-apply-databricks-manage`."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,128}$", var.name))
    error_message = "name must be a valid IAM policy name: 1-128 characters from `A-Z a-z 0-9 + = , . @ _ -`."
  }
}

variable "name_root" {
  description = "Prefix of resource names, in kebab-case. With `<p>` = `<name_root>-<project>`, the buckets are `<p>-databricks-root` and `<p>-databricks-catalog`."
  type        = string
  default     = "jwall-engineering"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name_root))
    error_message = "name_root must be kebab-case: lowercase letters, digits and single hyphens."
  }
}

variable "project" {
  description = "Project name in kebab-case, for example `databricks-poc`. Bucket names are built from `<name_root>-<project>` and EC2 is scoped by the `Project` tag."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.project))
    error_message = "project must be kebab-case: lowercase letters, digits and single hyphens (e.g. `databricks-poc`)."
  }
}

variable "secret_parameter_arn" {
  description = "ARN of the one SSM SecureString parameter holding the Databricks credential, for example `arn:aws:ssm:us-east-1:123456789012:parameter/jwall-engineering/databricks-poc/databricks`. The policy may read and decrypt this parameter only."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:ssm:us-east-1:[0-9]{12}:parameter/[A-Za-z0-9_.\\-/]+$", var.secret_parameter_arn))
    error_message = "secret_parameter_arn must be the ARN of one SSM parameter in us-east-1, with no wildcard, for example `arn:aws:ssm:us-east-1:123456789012:parameter/jwall-engineering/databricks-poc/databricks`; change secret_parameter_arn."
  }
}

variable "events_object_arn" {
  description = "Object ARN pattern of the project's event log, `arn:aws:s3:::jwall-engineering-databricks-audit-logs/events/project=<project>/*`. The policy may only put objects there: no read, no delete."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]/events/project=${var.project}/\\*$", var.events_object_arn))
    error_message = "events_object_arn must be the audit bucket's `events/project=<project>/*` object ARN for this project, for example `arn:aws:s3:::jwall-engineering-databricks-audit-logs/events/project=databricks-poc/*`, with project (`${var.project}`); change events_object_arn."
  }
}
