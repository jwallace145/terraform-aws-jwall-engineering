variable "aws_service_name" {
  description = "The service principal the role is linked to, for example `spot.amazonaws.com` (`AWSServiceRoleForEC2Spot`, which EC2 needs before the first Spot launch in an account)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?\\.amazonaws\\.com$", var.aws_service_name))
    error_message = "aws_service_name must be an AWS service principal like `spot.amazonaws.com`."
  }
}

variable "description" {
  description = "The role's description. Set it to an existing role's current description to adopt the role without a change; `null` leaves it unset."
  type        = string
  default     = null

  validation {
    condition     = var.description == null || try(length(var.description) <= 1000, false)
    error_message = "description must be at most 1,000 characters."
  }
}

variable "component" {
  description = "Value of the `Component` tag on the role."
  type        = string
  default     = "iam"

  validation {
    condition     = length(var.component) > 0
    error_message = "component must not be empty."
  }
}
