variable "name" {
  description = "IAM role name. Inline policies are named `<name>-<key>`."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.name))
    error_message = "name must be a valid IAM role name: 1-64 characters from `A-Z a-z 0-9 + = , . @ _ -`."
  }
}

variable "description" {
  description = "IAM role description, for example `terraform plan for owner/repo pull requests (read-only)`."
  type        = string
}

variable "repository" {
  description = "GitHub repository whose workflows may assume the role, as `owner/repo`."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?/[A-Za-z0-9._-]+$", var.repository))
    error_message = "repository must be an `owner/repo` string (e.g. `jwallace145/guitar`)."
  }
}

variable "owner_id" {
  description = "Numeric GitHub ID of the repository owner (`gh api users/<owner> --jq .id`). When set together with `repository_id`, the role also trusts GitHub's immutable subject form `repo:<owner>@<owner_id>/<name>@<repository_id>:...`."
  type        = string
  default     = null

  validation {
    condition     = var.owner_id == null || can(regex("^[0-9]+$", var.owner_id))
    error_message = "owner_id must be null or a numeric GitHub user/organization ID."
  }

  validation {
    condition     = (var.owner_id == null) == (var.repository_id == null)
    error_message = "owner_id and repository_id must be set together (or both left null)."
  }
}

variable "repository_id" {
  description = "Numeric GitHub ID of the repository (`gh api repos/<owner>/<repo> --jq .id`). When set together with `owner_id`, the role also trusts GitHub's immutable subject form."
  type        = string
  default     = null

  validation {
    condition     = var.repository_id == null || can(regex("^[0-9]+$", var.repository_id))
    error_message = "repository_id must be null or a numeric GitHub repository ID."
  }
}

variable "oidc_provider_arn" {
  description = "ARN of the account's GitHub Actions OIDC provider (`token.actions.githubusercontent.com`)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be `arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com`."
  }
}

variable "subjects" {
  description = "Subject suffixes the role trusts, appended to `repo:<repository>:` (and to the immutable prefix when the IDs are set). For example `[\"pull_request\"]` or `[\"environment:prod\"]`."
  type        = list(string)

  validation {
    condition     = length(var.subjects) > 0
    error_message = "subjects must contain at least one suffix (e.g. `pull_request`)."
  }

  validation {
    condition     = alltrue([for s in var.subjects : length(s) > 0 && !startswith(s, ":")])
    error_message = "every subject must be a non-empty suffix without a leading colon (e.g. `environment:prod`, not `:environment:prod`)."
  }
}

variable "trust_statement_sid" {
  description = "Sid of the single trust-policy statement. Only the trust policy JSON changes with it; set it to the Sid an existing role already uses to adopt the role without a diff."
  type        = string
  default     = "GitHubOidc"

  validation {
    condition     = can(regex("^[A-Za-z0-9]+$", var.trust_statement_sid))
    error_message = "trust_statement_sid must be alphanumeric."
  }
}

variable "inline_policies" {
  description = "Inline policies to attach, keyed by suffix. Each value is an IAM policy document object (`{ Version = \"2012-10-17\", Statement = [...] }`) that becomes `aws_iam_role_policy.this[<key>]` named `<name>-<key>` with `policy = jsonencode(value)`."
  # `any`, not `map(any)`: map(any) forces every document to one shared type,
  # which rejects two policies whose statements have different shapes.
  type    = any
  default = {}

  validation {
    condition     = can(keys(var.inline_policies))
    error_message = "inline_policies must be a map of policy-name suffix to policy document object."
  }

  validation {
    condition     = alltrue([for k, p in var.inline_policies : can(regex("^[A-Za-z0-9+=,.@_-]+$", k))])
    error_message = "every inline_policies key must be a valid IAM policy-name fragment (`A-Z a-z 0-9 + = , . @ _ -`)."
  }

  validation {
    condition     = alltrue([for k, p in var.inline_policies : can(p.Statement)])
    error_message = "every inline_policies value must be a policy document object with a `Statement` attribute."
  }
}

variable "managed_policy_arns" {
  description = "ARNs of managed policies to attach. Each becomes `aws_iam_role_policy_attachment.this[<arn>]`."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.managed_policy_arns : can(regex("^arn:aws:iam::(aws|[0-9]{12}):policy/.+$", a))])
    error_message = "every managed_policy_arns entry must be an IAM policy ARN (`arn:aws:iam::aws:policy/...` or `arn:aws:iam::<account-id>:policy/...`)."
  }
}

variable "managed_policies" {
  description = "Managed policies to attach, keyed by a name that is known at plan time. Each becomes `aws_iam_role_policy_attachment.keyed[<key>]`. Unlike `managed_policy_arns`, the ARNs may be unknown until apply, so policies created in the same run can be attached."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, a in var.managed_policies : length(k) > 0])
    error_message = "every managed_policies key must be non-empty."
  }

  validation {
    condition     = alltrue([for k, a in var.managed_policies : can(regex("^arn:aws:iam::(aws|[0-9]{12}):policy/.+$", a))])
    error_message = "every managed_policies value must be an IAM policy ARN (`arn:aws:iam::aws:policy/...` or `arn:aws:iam::<account-id>:policy/...`)."
  }
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds for the role."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds."
  }
}

variable "name_tag" {
  description = "Value of the `Name` tag. Left `null`, the module sets no `Name` tag and `Component` is the only tag it adds."
  type        = string
  default     = null
}

variable "component" {
  description = "Value of the `Component` tag on the role."
  type        = string

  validation {
    condition     = length(var.component) > 0
    error_message = "component must not be empty."
  }
}
