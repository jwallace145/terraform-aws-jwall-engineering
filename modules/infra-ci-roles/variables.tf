variable "name_root" {
  description = "Prefix of every role, policy and bucket the apply role may manage, in kebab-case. Roles are named `<name_root>-<project>-ci-{plan,apply}`."
  type        = string
  default     = "jwall-engineering"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name_root))
    error_message = "name_root must be kebab-case: lowercase letters, digits and single hyphens."
  }
}

variable "project" {
  description = "Project of the foundation stack in kebab-case, for example `infra`. Roles are named `<name_root>-<project>-ci-{plan,apply}`."
  type        = string
  default     = "infra"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.project))
    error_message = "project must be kebab-case: lowercase letters, digits and single hyphens."
  }

  validation {
    condition     = length("${var.name_root}-${var.project}-ci-apply") <= 64
    error_message = "name_root and project are too long: `<name_root>-<project>-ci-apply` must fit IAM's 64-character role name limit."
  }
}

variable "repository" {
  description = "GitHub repository of the foundation stack, as `owner/repo`. Both roles trust only this repository."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?/[A-Za-z0-9._-]+$", var.repository))
    error_message = "repository must be an `owner/repo` string (e.g. `jwallace145/jwall-engineering-infra`)."
  }
}

variable "owner_id" {
  description = "Numeric GitHub ID of the repository owner (`gh api users/<owner> --jq .id`). When set together with `repository_id`, the roles also trust GitHub's immutable subject form `repo:<owner>@<owner_id>/<name>@<repository_id>:...`."
  type        = string
  default     = null
}

variable "repository_id" {
  description = "Numeric GitHub ID of the repository (`gh api repos/<owner>/<repo> --jq .id`). When set together with `owner_id`, the roles also trust GitHub's immutable subject form."
  type        = string
  default     = null
}

variable "oidc_provider_arn" {
  description = "ARN of the account's GitHub Actions OIDC provider (`token.actions.githubusercontent.com`). This module does not manage the provider and grants no permissions on it."
  type        = string
}

variable "apply_environment" {
  description = "GitHub environment whose jobs may assume the apply role. The apply role trusts `environment:<apply_environment>`; the plan role trusts `pull_request`."
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]*$", var.apply_environment))
    error_message = "apply_environment must be a GitHub environment name of letters, digits, `_` and `-`."
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

variable "state_key" {
  description = "This stack's own state key, for example `project=infra/env=prod/infra-prod.tfstate`. Must match the backend configuration. The roles may only touch this object and its `.tflock`."
  type        = string

  validation {
    condition     = can(regex("^[^/*?][^*?]*\\.tfstate$", var.state_key))
    error_message = "state_key must be a relative S3 key ending in `.tfstate`, without a leading slash and without `*` or `?` anywhere, because both are IAM wildcards (e.g. `project=infra/env=prod/infra-prod.tfstate`)."
  }
}

variable "hosted_zone_arn" {
  description = "ARN of the hosted zone the apply role may change records in (output `arn` of `hosted-zone`)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:route53:::hostedzone/Z[A-Z0-9]{5,31}$", var.hosted_zone_arn))
    error_message = "hosted_zone_arn must look like `arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ`."
  }
}

variable "managed_bucket_patterns" {
  description = "Bucket name patterns the apply role gets `s3:*` on, for the buckets and their objects. Defaults to `[\"<name_root>-*\"]`, which covers every `site-bucket`."
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
  description = "Managed policy ARN patterns the apply role may attach with `iam:AttachRolePolicy` (an `ArnLike` allow-list). Defaults to `ReadOnlyAccess` and the account's `<name_root>-*` customer-managed policies."
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
