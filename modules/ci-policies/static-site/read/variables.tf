variable "name" {
  description = "Name of the managed policy, for example `jwall-engineering-guitar-ci-apply-static-site-deploy`."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,128}$", var.name))
    error_message = "name must be a valid IAM policy name: 1-128 characters from `A-Z a-z 0-9 + = , . @ _ -`."
  }
}

variable "name_root" {
  description = "Prefix of resource names, in kebab-case. CloudFront Functions are scoped to `<name_root>-<project>-*`."
  type        = string
  default     = "jwall-engineering"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name_root))
    error_message = "name_root must be kebab-case: lowercase letters, digits and single hyphens."
  }
}

variable "project" {
  description = "Project name in kebab-case. Tag-scoped statements require `Project = <project>`."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.project))
    error_message = "project must be kebab-case: lowercase letters, digits and single hyphens (e.g. `my-site`)."
  }
}

variable "bucket_arn" {
  description = "ARN of the project's site bucket (output `arn` of the `site-bucket` module)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:s3:::[a-z0-9.-]{3,63}$", var.bucket_arn))
    error_message = "bucket_arn must be an S3 bucket ARN like `arn:aws:s3:::bucket-name` (no trailing path)."
  }
}

variable "zone_id" {
  description = "Route 53 hosted zone ID the project's records live in."
  type        = string

  validation {
    condition     = can(regex("^Z[A-Z0-9]{5,31}$", var.zone_id))
    error_message = "zone_id must be a Route 53 hosted zone ID (e.g. `Z0123456789ABCDEFGHIJ`)."
  }
}
