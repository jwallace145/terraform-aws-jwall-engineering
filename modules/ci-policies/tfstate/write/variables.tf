variable "name" {
  description = "Name of the managed policy, for example `jwall-engineering-guitar-ci-plan-tfstate-read`."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,128}$", var.name))
    error_message = "name must be a valid IAM policy name: 1-128 characters from `A-Z a-z 0-9 + = , . @ _ -`."
  }
}

variable "bucket_arn" {
  description = "ARN of the Terraform state bucket (output `arn` of `tfstate-bucket`)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:s3:::[a-z0-9.-]{3,63}$", var.bucket_arn))
    error_message = "bucket_arn must be an S3 bucket ARN like `arn:aws:s3:::bucket-name` (no trailing path)."
  }
}

variable "key" {
  description = "One stack's state key, for example `project=infra/env=prod/infra-prod.tfstate`. The policy covers this object and its `.tflock`. Set exactly one of `key` and `prefix`."
  type        = string
  default     = null

  validation {
    condition     = var.key == null || can(regex("^[^/*?][^*?]*\\.tfstate$", var.key))
    error_message = "key must be a relative S3 key ending in `.tfstate`, without a leading slash and without `*` or `?` anywhere, because both are IAM wildcards (e.g. `project=infra/env=prod/infra-prod.tfstate`)."
  }

  validation {
    condition     = (var.key == null) != (var.prefix == null)
    error_message = "set exactly one of key and prefix."
  }
}

variable "prefix" {
  description = "A key prefix every state object of a project lives under, for example `project=guitar/`. The policy covers every object under it. Set exactly one of `key` and `prefix`."
  type        = string
  default     = null

  validation {
    condition     = var.prefix == null || can(regex("^[^/*?][^*?]*/$", var.prefix))
    error_message = "prefix must be a relative S3 key prefix ending in `/`, without a leading slash and without `*` or `?` anywhere, because both are IAM wildcards (e.g. `project=guitar/`)."
  }
}
