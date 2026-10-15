variable "name" {
  description = "Name of the managed policy, for example `jwall-engineering-guitar-ci-apply-static-site-deploy`."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,128}$", var.name))
    error_message = "name must be a valid IAM policy name: 1-128 characters from `A-Z a-z 0-9 + = , . @ _ -`."
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
