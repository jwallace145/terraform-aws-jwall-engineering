variable "name" {
  description = "Name of the bucket, for example `jwall-engineering-rusty-chess-nnue`. Also the value of its `Name` tag."
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

variable "prefix" {
  description = "Key prefix the project's data lives under, ending in `/`, for example `data/`. Writers and readers are granted this prefix only."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9][a-z0-9._=-]*/)+$", var.prefix))
    error_message = "prefix must be one or more path segments of lowercase letters, digits, `.`, `_`, `=` and `-`, each starting with a letter or digit, ending in `/` and without a leading `/` (e.g. `data/`)."
  }
}

variable "transition_days" {
  description = "Days after which objects move to S3 Intelligent-Tiering. 0 moves them at once (at the next daily lifecycle run). Objects under 128 KB stay in S3 Standard."
  type        = number
  default     = 0

  validation {
    condition     = var.transition_days >= 0 && floor(var.transition_days) == var.transition_days
    error_message = "transition_days must be a whole number of days, 0 or more."
  }
}

variable "writer_role_names" {
  description = "Roles in this account that may add objects under the prefix: an inline policy on each grants `s3:PutObject` (and `s3:AbortMultipartUpload` for its own failed uploads) under the prefix and `s3:ListBucket` limited to it. Never read, delete or overwrite protection: writers only add."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for r in var.writer_role_names : can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", r))])
    error_message = "writer_role_names must be IAM role names (not ARNs)."
  }
}

variable "reader_role_arns" {
  description = "IAM role ARNs granted `s3:GetObject` under the prefix and `s3:ListBucket` limited to it, through the bucket policy. The account's administrators can read without being listed."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for r in var.reader_role_arns : can(regex("^arn:aws:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", r))])
    error_message = "reader_role_arns must be IAM role ARNs like arn:aws:iam::123456789012:role/name."
  }
}

variable "role_grants" {
  description = "Roles in this account granted narrower access than a writer or reader: `read` and `write` are sub-prefixes of `prefix` (each ending in `/`, for example `selfplay/`). An inline policy on each role grants `s3:GetObject` under each `read` sub-prefix, `s3:PutObject` (and `s3:AbortMultipartUpload`) under each `write` sub-prefix, and `s3:ListBucket` limited to all of them. Never delete. Keys are role names."
  type = map(object({
    read  = optional(list(string), [])
    write = optional(list(string), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for g in values(var.role_grants) : alltrue([
        for p in concat(g.read, g.write) : can(regex("^([a-z0-9][a-z0-9._=-]*/)+$", p))
      ])
    ])
    error_message = "role_grants read and write entries must be sub-prefixes like `selfplay/`: path segments ending in `/`, without a leading `/`."
  }

  validation {
    condition     = alltrue([for g in values(var.role_grants) : length(g.read) + length(g.write) > 0])
    error_message = "each role_grants entry must grant at least one read or write sub-prefix."
  }
}
