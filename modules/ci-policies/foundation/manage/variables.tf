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

variable "attachable_policy_arns" {
  description = "Managed policy ARN patterns the policy allows attaching with `iam:AttachRolePolicy` (an `ArnLike` allow-list). Defaults to the account's `<name_root>-*` customer-managed policies, which include every policy `ci-policies` creates."
  type        = list(string)
  default     = null

  validation {
    condition     = var.attachable_policy_arns == null || length(coalesce(var.attachable_policy_arns, [])) > 0
    error_message = "attachable_policy_arns must be null (use the default) or a non-empty list."
  }

  validation {
    condition     = alltrue([for a in coalesce(var.attachable_policy_arns, ["arn:aws:iam::aws:policy/x"]) : can(regex("^arn:aws:iam::(aws|[0-9]{12}):policy/[^*?/][^ ]*$", a))])
    error_message = "every attachable policy must be an IAM policy ARN or ARN pattern with a literal first character after `policy/` (`arn:aws:iam::aws:policy/ReadOnlyAccess`, `arn:aws:iam::<account-id>:policy/team-*`). A bare `*` would allow attaching any policy, including AdministratorAccess."
  }
}
