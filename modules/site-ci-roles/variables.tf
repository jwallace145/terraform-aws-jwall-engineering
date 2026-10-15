variable "project" {
  description = "Project name in kebab-case. Roles are named `jwall-engineering-<project>-ci-{plan,preview,apply}` and permissions are scoped to resources tagged `Project = <project>`."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.project))
    error_message = "project must be kebab-case: lowercase letters, digits and single hyphens (e.g. `my-site`)."
  }

  validation {
    condition     = length(var.project) <= 30
    error_message = "project must be at most 30 characters so role names stay within IAM's 64-character limit."
  }
}

variable "repository" {
  description = "GitHub repository whose workflows may assume the roles, as `owner/repo`."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?/[A-Za-z0-9._-]+$", var.repository))
    error_message = "repository must be an `owner/repo` string (e.g. `jwallace145/guitar`)."
  }
}

variable "bucket_arn" {
  description = "ARN of the project's site bucket (output `arn` of the `site-bucket` module)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:s3:::[a-z0-9.-]{3,63}$", var.bucket_arn))
    error_message = "bucket_arn must be an S3 bucket ARN like `arn:aws:s3:::bucket-name` (no trailing path)."
  }
}

variable "state_bucket_arn" {
  description = "ARN of the shared Terraform state bucket. The project's state lives under the key prefix `project=<project>/`."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:s3:::[a-z0-9.-]{3,63}$", var.state_bucket_arn))
    error_message = "state_bucket_arn must be an S3 bucket ARN like `arn:aws:s3:::bucket-name` (no trailing path)."
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

variable "zone_id" {
  description = "Route 53 hosted zone ID in which the project may change records."
  type        = string

  validation {
    condition     = can(regex("^Z[A-Z0-9]{5,31}$", var.zone_id))
    error_message = "zone_id must be a Route 53 hosted zone ID (e.g. `Z0123456789ABCDEFGHIJ`)."
  }
}

variable "record_names" {
  description = "FQDNs the project may manage in the hosted zone, including the wildcard preview name (for example `[\"guitar.example.com\", \"dev.guitar.example.com\", \"*.preview.guitar.example.com\"]`). ACM validation CNAMEs for these names are allowed automatically."
  type        = list(string)

  validation {
    condition     = length(var.record_names) > 0
    error_message = "record_names must contain at least one FQDN."
  }

  validation {
    condition = alltrue([
      for n in var.record_names : can(regex("^(\\*\\.)?([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", n))
    ])
    error_message = "every record name must be a lowercase FQDN without a trailing dot, optionally prefixed with `*.` (e.g. `*.preview.guitar.example.com`)."
  }
}

variable "owner_id" {
  description = "Numeric GitHub ID of the repository owner (`gh api users/<owner> --jq .id`). When set together with `repository_id`, the roles also trust GitHub's immutable subject form `repo:<owner>@<owner_id>/<name>@<repository_id>:...`."
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
  description = "Numeric GitHub ID of the repository (`gh api repos/<owner>/<repo> --jq .id`). When set together with `owner_id`, the roles also trust GitHub's immutable subject form."
  type        = string
  default     = null

  validation {
    condition     = var.repository_id == null || can(regex("^[0-9]+$", var.repository_id))
    error_message = "repository_id must be null or a numeric GitHub repository ID."
  }
}
