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

variable "admin_principal_arns" {
  description = "IAM principal ARNs exempt from every deny in the bucket policy except TLS, for example the admin user and the role that applies this bucket. Being exempt grants nothing; the principal's own IAM policies still decide what it can do. Required when `prefix_access` is set, so the policy can always be changed by someone."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.admin_principal_arns : can(regex("^arn:aws:iam::[0-9]{12}:(root|user/[^*?]+|role/[^*?]+)$", a))])
    error_message = "every admin principal must be an exact IAM user, role or root ARN without wildcards (e.g. `arn:aws:iam::123456789012:user/admin`)."
  }
}

variable "prefix_access" {
  description = "Hardens the bucket policy when set: map of state key prefix to the principals that may `read` and `write` objects under it. Each key matches `<key>*`, so a full state key such as `project=infra/env=prod/infra-prod.tfstate` also covers its `.tflock`. Everyone else, including principals with `s3:*`, is denied object access; readers may only write `.tflock` objects. Leave empty for a TLS-only policy."
  type = map(object({
    read  = optional(list(string), [])
    write = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.prefix_access : can(regex("^[^/*?][^*?]*$", k))])
    error_message = "every prefix_access key must be a relative key prefix without a leading slash and without `*` or `?`, because both are IAM wildcards (e.g. `project=guitar/`)."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.prefix_access : [for o in keys(var.prefix_access) : o == k || !startswith(o, k)]
    ]))
    error_message = "prefix_access keys must not overlap: no key may be a prefix of another."
  }

  validation {
    condition     = alltrue([for k, v in var.prefix_access : length(concat(v.read, v.write)) > 0])
    error_message = "every prefix_access entry must list at least one read or write principal."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.prefix_access : [for a in concat(v.read, v.write) : can(regex("^arn:aws:iam::[0-9]{12}:(root|user/[^*?]+|role/[^*?]+)$", a))]
    ]))
    error_message = "every prefix_access principal must be an exact IAM user, role or root ARN without wildcards."
  }

  validation {
    condition     = length(var.prefix_access) == 0 || length(var.admin_principal_arns) > 0
    error_message = "admin_principal_arns must not be empty when prefix_access is set; otherwise nobody but the root user could change the bucket policy."
  }
}
