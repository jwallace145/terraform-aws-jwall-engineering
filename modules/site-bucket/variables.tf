variable "project" {
  description = "Project name in kebab-case. The bucket is named `jwall-engineering-<project>`."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.project))
    error_message = "project must be kebab-case: lowercase letters, digits and single hyphens (e.g. `my-site`)."
  }

  validation {
    condition     = length(var.project) <= 30
    error_message = "project must be at most 30 characters so the bucket name stays within S3's 63-character limit."
  }
}

variable "admin_principal_arns" {
  description = "IAM principal ARNs exempt from every deny in the bucket policy except TLS, for example the admin user and the role that applies this bucket. Being exempt grants nothing; the principal's own IAM policies still decide what it can do. Required when `prefix_writers` is set, so the policy can always be changed by someone."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.admin_principal_arns : can(regex("^arn:aws:iam::[0-9]{12}:(root|user/[^*?]+|role/[^*?]+)$", a))])
    error_message = "every admin principal must be an exact IAM user, role or root ARN without wildcards (e.g. `arn:aws:iam::123456789012:user/admin`)."
  }
}

variable "prefix_writers" {
  description = "Hardens the bucket policy when set: map of key prefix (ending in `/`) to the principals that may write objects under it, for example `{ \"prod/\" = [<apply role>], \"dev/\" = [<apply role>], \"previews/\" = [<preview role>] }`. Everyone else, including principals with `s3:*`, is denied writes, and only `admin_principal_arns` may write outside these prefixes or change the bucket's configuration. Reads are not restricted: the content is public through CloudFront. Leave empty for the TLS and CloudFront statements only."
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.prefix_writers : can(regex("^[^/*?][^*?]*/$", k))])
    error_message = "every prefix_writers key must be a relative key prefix ending in `/`, without a leading slash and without `*` or `?` (e.g. `prod/`)."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.prefix_writers : [for o in keys(var.prefix_writers) : o == k || !startswith(o, k)]
    ]))
    error_message = "prefix_writers keys must not overlap: no key may be a prefix of another."
  }

  validation {
    condition     = alltrue([for k, v in var.prefix_writers : length(v) > 0])
    error_message = "every prefix_writers entry must list at least one principal."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.prefix_writers : [for a in v : can(regex("^arn:aws:iam::[0-9]{12}:(root|user/[^*?]+|role/[^*?]+)$", a))]
    ]))
    error_message = "every prefix_writers principal must be an exact IAM user, role or root ARN without wildcards."
  }

  validation {
    condition     = length(var.prefix_writers) == 0 || length(var.admin_principal_arns) > 0
    error_message = "admin_principal_arns must not be empty when prefix_writers is set; otherwise nobody but the root user could change the bucket policy."
  }
}
