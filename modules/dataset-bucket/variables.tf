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
  description = "Roles in this account granted narrower access than a writer or reader. `read`, `write` and `write_once` are lists of sub-prefixes of `prefix`, each ending in `/` (for example `selfplay/`). An inline policy on each role grants `s3:GetObject` under each `read` sub-prefix, `s3:PutObject` (and `s3:AbortMultipartUpload`) under each `write` sub-prefix, and `s3:ListBucket` limited to all three lists. `write_once` sub-prefixes are add-only: `s3:PutObject` is allowed there only with `If-None-Match: *` (for example `aws s3 cp --no-overwrite`), so S3 refuses to overwrite an existing object, and `CopyObject` into such a prefix is refused because it carries no such condition. A grant never deletes. Keys are role names. The guarantee holds only for what this module controls: if any grant has `write_once`, `writer_role_names` must be empty, no grant's `write` may overlap any grant's `write_once`, and no `expire_prefixes` key may overlap one (overlap means either string starts with the other). Policies this module does not manage, such as an administrator's or another inline policy on the same role, can still overwrite."
  type = map(object({
    read  = optional(list(string), [])
    write = optional(list(string), [])
    # Add-only: objects can be created but never overwritten (S3 conditional writes).
    write_once = optional(list(string), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for g in values(var.role_grants) : alltrue([
        for p in concat(g.read, g.write, g.write_once) : can(regex("^([a-z0-9][a-z0-9._=-]*/)+$", p))
      ])
    ])
    error_message = "role_grants read, write and write_once entries must be sub-prefixes like `selfplay/`: path segments ending in `/`, without a leading `/`."
  }

  validation {
    condition     = alltrue([for g in values(var.role_grants) : length(g.read) + length(g.write) + length(g.write_once) > 0])
    error_message = "each role_grants entry must grant at least one read, write or write_once sub-prefix."
  }

  validation {
    condition     = !anytrue([for g in values(var.role_grants) : length(g.write_once) > 0]) || length(var.writer_role_names) == 0
    error_message = "writer_role_names must be empty when any role_grants entry has write_once: a writer's plain PutObject under the whole prefix would overwrite write-once objects."
  }

  validation {
    condition = !anytrue(flatten([
      for g in values(var.role_grants) : [
        for o in g.write_once : [
          for h in values(var.role_grants) : [for w in h.write : startswith(w, o) || startswith(o, w)]
        ]
      ]
    ]))
    error_message = "no role_grants write sub-prefix, in any grant, may overlap a write_once sub-prefix (either starting with the other): the plain write would allow overwrites."
  }
}

variable "versioning" {
  description = "Keep previous versions of overwritten or deleted objects. Off by default: datasets are write-once, so versioning would only store an accidental re-upload twice. Setting it back to false suspends versioning rather than removing existing versions."
  type        = bool
  default     = false
}

variable "expire_noncurrent_days" {
  description = "Days after which noncurrent object versions are permanently deleted, across the whole bucket. Requires `versioning = true`. `null` keeps them forever."
  type        = number
  default     = null

  validation {
    condition     = var.expire_noncurrent_days == null || (var.expire_noncurrent_days >= 1 && floor(var.expire_noncurrent_days) == var.expire_noncurrent_days)
    error_message = "expire_noncurrent_days must be a whole number of days, 1 or more."
  }

  validation {
    condition     = var.expire_noncurrent_days == null || var.versioning
    error_message = "expire_noncurrent_days only applies to noncurrent versions, so it requires versioning = true."
  }
}

variable "expire_prefixes" {
  description = "Sub-prefixes of `prefix` whose objects expire after the given number of days, for example `{ \"tmp/\" = 30 }` under `data/` expires `data/tmp/` after 30 days. Keys end in `/`, must not overlap each other or any `role_grants` `write_once` sub-prefix (either string starting with the other), and must give distinct rule ids (`a/b/` and `a-b/` both give `expire-a-b-`). Nothing outside the named sub-prefixes expires. On a versioned bucket, expiry only adds a delete marker: without `expire_noncurrent_days` the data is kept, and still billed."
  type        = map(number)
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.expire_prefixes) : can(regex("^([a-z0-9][a-z0-9._=-]*/)+$", k))])
    error_message = "expire_prefixes keys must be sub-prefixes like `tmp/`: path segments ending in `/`, without a leading `/`."
  }

  validation {
    condition     = alltrue([for d in values(var.expire_prefixes) : d >= 1 && floor(d) == d])
    error_message = "expire_prefixes values must be a whole number of days, 1 or more."
  }

  validation {
    condition = !anytrue(flatten([
      for k in keys(var.expire_prefixes) : [
        for j in keys(var.expire_prefixes) : startswith(j, k) if j != k
      ]
    ]))
    error_message = "expire_prefixes keys must not overlap (such as `tmp/` and `tmp/keep/`): the nested prefix would get two rules, and S3 applies the shorter expiry to it too."
  }

  validation {
    condition     = length(distinct([for k in keys(var.expire_prefixes) : replace(k, "/", "-")])) == length(var.expire_prefixes)
    error_message = "expire_prefixes keys must give distinct rule ids: `a/b/` and `a-b/` both become `expire-a-b-`."
  }

  validation {
    condition = !anytrue(flatten([
      for k in keys(var.expire_prefixes) : [
        for g in values(var.role_grants) : [for o in g.write_once : startswith(k, o) || startswith(o, k)]
      ]
    ]))
    error_message = "expire_prefixes keys must not overlap a role_grants write_once sub-prefix (either starting with the other): expiry would delete write-once objects."
  }
}
