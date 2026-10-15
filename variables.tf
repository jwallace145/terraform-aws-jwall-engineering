variable "bucket_name" {
  description = "Name of the project's site bucket (output `name` of `site-bucket`, or `bucket_name` of `context`)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name (3-63 lowercase alphanumerics, dots and hyphens)."
  }
}

variable "bucket_regional_domain_name" {
  description = "Regional domain name of the site bucket (output `regional_domain_name` of `site-bucket`)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.s3\\.[a-z0-9-]+\\.amazonaws\\.com$", var.bucket_regional_domain_name))
    error_message = "bucket_regional_domain_name must look like `<bucket>.s3.<region>.amazonaws.com`."
  }
}

variable "domain_name" {
  description = "Production FQDN, for example `guitar.jwall.engineering`. Served from `<bucket>/prod`; previews are served from `pr-<n>.preview.<domain_name>`."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.domain_name))
    error_message = "domain_name must be a lowercase FQDN without a trailing dot (e.g. `guitar.jwall.engineering`)."
  }
}

variable "dev_domain_name" {
  description = "Optional FQDN for the dev environment, served from `<bucket>/dev` (for example `dev.guitar.jwall.engineering`). Set to `null` to skip the dev distribution."
  type        = string
  default     = null

  validation {
    condition     = var.dev_domain_name == null || can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.dev_domain_name))
    error_message = "dev_domain_name must be null or a lowercase FQDN without a trailing dot."
  }
}

variable "enable_preview" {
  description = "Whether to create the `*.preview.<domain_name>` distribution for pull-request previews."
  type        = bool
  default     = true
}

variable "zone_id" {
  description = "Route 53 hosted zone ID that contains `domain_name` (and `dev_domain_name`)."
  type        = string

  validation {
    condition     = can(regex("^Z[A-Z0-9]{5,31}$", var.zone_id))
    error_message = "zone_id must be a Route 53 hosted zone ID (e.g. `Z0123456789ABCDEFGHIJ`)."
  }
}
