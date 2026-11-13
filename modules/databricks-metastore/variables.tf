variable "name" {
  description = "Name of the metastore. There is one metastore per region per Databricks account, shared by every workspace in that region."
  type        = string
  default     = "jwall-engineering-us-east-1"

  validation {
    condition     = length(var.name) > 0
    error_message = "name must not be empty."
  }
}

variable "region" {
  description = "Region of the metastore. Only `us-east-1` is supported: every workspace of the account lives there."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.region == "us-east-1"
    error_message = "region must be \"us-east-1\", the only region this library supports; change the region variable."
  }
}

variable "admin_group_name" {
  description = "Account-level group that owns the metastore."
  type        = string
  default     = "jwall-engineering-metastore-admins"

  validation {
    condition     = length(var.admin_group_name) > 0
    error_message = "admin_group_name must not be empty."
  }
}

variable "admin_user_names" {
  description = "Databricks user names (email addresses) of the people who administer the metastore, for example `[\"owner@example.com\"]`. Each user must already exist in the account."
  type        = list(string)

  validation {
    condition     = alltrue([for u in var.admin_user_names : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", u))])
    error_message = "every entry of admin_user_names must be an email address such as owner@example.com; change the admin_user_names variable."
  }
}

variable "service_principal_application_id" {
  description = "Application (client) ID of the account-level service principal that automation authenticates as. It joins the admin group so the foundation stack keeps control of the metastore."
  type        = string

  validation {
    condition     = length(var.service_principal_application_id) > 0
    error_message = "service_principal_application_id must not be empty; pass the application ID of the automation service principal."
  }
}
