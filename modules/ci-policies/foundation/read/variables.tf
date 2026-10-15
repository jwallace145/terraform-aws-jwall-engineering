variable "name" {
  description = "Name of the managed policy, for example `jwall-engineering-infra-ci-apply-foundation-manage`."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,128}$", var.name))
    error_message = "name must be a valid IAM policy name: 1-128 characters from `A-Z a-z 0-9 + = , . @ _ -`."
  }
}

variable "name_root" {
  description = "Prefix of every role, policy and bucket the foundation stack manages, in kebab-case."
  type        = string
  default     = "jwall-engineering"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name_root))
    error_message = "name_root must be kebab-case: lowercase letters, digits and single hyphens."
  }
}

variable "state_bucket_arn" {
  description = "ARN of the Terraform state bucket (output `arn` of `tfstate-bucket`)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:s3:::[a-z0-9.-]{3,63}$", var.state_bucket_arn))
    error_message = "state_bucket_arn must be an S3 bucket ARN like `arn:aws:s3:::bucket-name` (no trailing path)."
  }
}

variable "hosted_zone_arn" {
  description = "ARN of the hosted zone the foundation stack manages (output `arn` of `hosted-zone`)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:route53:::hostedzone/Z[A-Z0-9]{5,31}$", var.hosted_zone_arn))
    error_message = "hosted_zone_arn must look like `arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ`."
  }
}

variable "managed_bucket_patterns" {
  description = "Bucket name patterns the foundation stack manages. Defaults to `[\"<name_root>-*\"]`, which covers every `site-bucket`. The policies reach the buckets themselves, never their objects."
  type        = list(string)
  default     = null

  validation {
    condition     = var.managed_bucket_patterns == null || length(coalesce(var.managed_bucket_patterns, [])) > 0
    error_message = "managed_bucket_patterns must be null (use the default) or a non-empty list."
  }

  validation {
    condition     = alltrue([for p in coalesce(var.managed_bucket_patterns, ["x"]) : can(regex("^[a-z0-9.*-]+$", p)) && p != "*"])
    error_message = "every managed bucket pattern must be a bucket name or prefix pattern (lowercase letters, digits, `.`, `-`, `*`) and not `*` alone."
  }
}

variable "oidc_provider_arn" {
  description = "ARN of the account's GitHub Actions OIDC provider. The policy may read it, so a data source can look it up."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be `arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com`."
  }
}
