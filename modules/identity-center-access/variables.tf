variable "instance_arn" {
  description = "ARN of the IAM Identity Center organization instance, from `data.aws_ssoadmin_instances` (for example `arn:aws:sso:::instance/ssoins-0123456789abcdef`). The instance must already be enabled in the console; this module cannot create one."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:sso:::instance/ssoins-[0-9a-f]{16}$", var.instance_arn))
    error_message = "instance_arn must look like `arn:aws:sso:::instance/ssoins-0123456789abcdef`."
  }
}

variable "identity_store_id" {
  description = "ID of the instance's identity store, from `data.aws_ssoadmin_instances` (for example `d-0123456789`)."
  type        = string

  validation {
    condition     = can(regex("^d-[0-9a-f]{10}$", var.identity_store_id))
    error_message = "identity_store_id must look like `d-0123456789`."
  }
}

variable "account_id" {
  description = "The AWS account the user gets the permission set in, as a 12-digit string."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "additional_account_ids" {
  description = "Other AWS accounts of the organization the user gets the same permission set in, as 12-digit strings. Identity Center provisions the permission set's role in each; `role_arn` is still the role in the account the provider runs in, so read another account's role ARN there (`aws iam list-roles --path-prefix /aws-reserved/sso.amazonaws.com/`)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.additional_account_ids : can(regex("^[0-9]{12}$", a))])
    error_message = "every additional account must be a 12-digit AWS account ID."
  }

  validation {
    condition     = !contains(var.additional_account_ids, var.account_id) && length(distinct(var.additional_account_ids)) == length(var.additional_account_ids)
    error_message = "additional_account_ids must not repeat `account_id` or each other."
  }
}

variable "user" {
  description = "The one Identity Center user who gets the permission set. `display_name` defaults to `<given_name> <family_name>`. The user is created without a password: set one at first sign-in through Identity Center's email one-time password, or generate one in the console."
  type = object({
    user_name    = string
    given_name   = string
    family_name  = string
    email        = string
    display_name = optional(string)
  })

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,128}$", var.user.user_name))
    error_message = "user.user_name must be 1-128 characters from `A-Z a-z 0-9 + = , . @ _ -`."
  }

  validation {
    condition     = trimspace(var.user.given_name) != "" && trimspace(var.user.family_name) != ""
    error_message = "user.given_name and user.family_name must not be empty."
  }

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.user.email))
    error_message = "user.email must be an email address."
  }
}

variable "permission_set_name" {
  description = "Name of the permission set. Identity Center provisions its IAM role as `AWSReservedSSO_<name>_<suffix>`, and the CLI profile's `sso_role_name` is this name."
  type        = string
  default     = "AdministratorAccess"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,32}$", var.permission_set_name))
    error_message = "permission_set_name must be 1-32 characters from `A-Z a-z 0-9 _ -`."
  }
}

variable "permission_set_description" {
  description = "Description of the permission set."
  type        = string
  default     = "Administrator access for the account owner"
}

variable "session_duration" {
  description = "How long each set of credentials (and each console session) from the permission set lasts, as an ISO-8601 duration in whole hours from `PT1H` to `PT12H`. The AWS CLI and SDKs renew credentials until the Identity Center sign-in itself expires."
  type        = string
  default     = "PT1H"

  validation {
    condition     = can(regex("^PT([1-9]|1[0-2])H$", var.session_duration))
    error_message = "session_duration must be whole hours from PT1H to PT12H, for example `PT1H`."
  }
}

variable "managed_policy_arns" {
  description = "Managed policies attached to the permission set. Defaults to `AdministratorAccess`."
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]

  validation {
    condition     = length(var.managed_policy_arns) > 0
    error_message = "managed_policy_arns must not be empty."
  }

  validation {
    condition     = alltrue([for a in var.managed_policy_arns : can(regex("^arn:aws:iam::(aws|[0-9]{12}):policy/[^*?]+$", a))])
    error_message = "every managed policy must be an IAM policy ARN without wildcards, for example `arn:aws:iam::aws:policy/AdministratorAccess`."
  }
}
