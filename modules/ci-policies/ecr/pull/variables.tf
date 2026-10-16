variable "name" {
  description = "Name of the managed policy, for example `jwall-engineering-guitar-ci-plan-ecr-pull`."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,128}$", var.name))
    error_message = "name must be a valid IAM policy name: 1-128 characters from `A-Z a-z 0-9 + = , . @ _ -`."
  }
}

variable "repository_arn" {
  description = "ARN of the ECR repository (output `arn` of `ecr-repository`)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:ecr:[a-z0-9-]+:[0-9]{12}:repository/[a-z0-9._/-]+$", var.repository_arn))
    error_message = "repository_arn must be an ECR repository ARN like `arn:aws:ecr:us-east-1:123456789012:repository/name`."
  }
}
