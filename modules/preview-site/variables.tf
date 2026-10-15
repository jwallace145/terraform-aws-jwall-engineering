variable "bucket_name" {
  description = "Name of the project's site bucket (output `name` of `site-bucket`, or `bucket_name` of `context`). Also used as the prefix of the CloudFront Function name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name (3-63 lowercase alphanumerics, dots and hyphens)."
  }
}

variable "bucket_regional_domain_name" {
  description = "Regional domain name of the site bucket (output `regional_domain_name` of `site-bucket`), used as the distribution origin."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.s3\\.[a-z0-9-]+\\.amazonaws\\.com$", var.bucket_regional_domain_name))
    error_message = "bucket_regional_domain_name must look like `<bucket>.s3.<region>.amazonaws.com`."
  }
}

variable "site_domain" {
  description = "The site's production FQDN, for example `guitar.jwall.engineering`. Previews are served from `pr-<n>.preview.<site_domain>`."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.site_domain))
    error_message = "site_domain must be a lowercase FQDN without a trailing dot (e.g. `guitar.jwall.engineering`)."
  }
}

variable "zone_id" {
  description = "Route 53 hosted zone ID that contains `site_domain`. Validation and wildcard alias records are created in it."
  type        = string

  validation {
    condition     = can(regex("^Z[A-Z0-9]{5,31}$", var.zone_id))
    error_message = "zone_id must be a Route 53 hosted zone ID (e.g. `Z0123456789ABCDEFGHIJ`)."
  }
}
