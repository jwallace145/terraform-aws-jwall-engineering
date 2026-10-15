variable "name" {
  description = "Name of the Terraform state bucket, for example `jwall-engineering-tfstate`. Also the value of its `Name` tag."
  type        = string

  validation {
    condition = (
      can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.name)) &&
      !can(regex("\\.\\.", var.name)) &&
      !can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", var.name))
    )
    error_message = "name must be a valid S3 bucket name: 3-63 characters of lowercase letters, digits, dots and hyphens, starting and ending with a letter or digit, without consecutive dots, and not an IP address."
  }
}

variable "component" {
  description = "Value of the `Component` tag on the bucket."
  type        = string
  default     = "terraform-state"

  validation {
    condition     = length(var.component) > 0
    error_message = "component must not be empty."
  }
}
