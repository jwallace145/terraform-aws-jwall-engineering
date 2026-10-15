variable "name" {
  description = "Zone name as a lowercase FQDN without a trailing dot, for example `jwall.engineering`."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.name))
    error_message = "name must be a lowercase FQDN without a trailing dot (e.g. `jwall.engineering`)."
  }
}

variable "comment" {
  description = "Zone comment. State who owns the zone and who owns its records, for example `zone owned by owner/infra; records owned by project repos`."
  type        = string

  validation {
    condition     = length(trimspace(var.comment)) > 0 && length(var.comment) <= 256
    error_message = "comment must be a non-empty string of at most 256 characters."
  }
}

variable "caa_issuers" {
  description = "Certificate authorities allowed to issue for the zone and its subdomains, as CAA `issue` domains. The default is the four Amazon CAs that ACM needs. An empty list creates no CAA record."
  type        = list(string)
  default     = ["amazon.com", "amazontrust.com", "awstrust.com", "amazonaws.com"]

  validation {
    condition     = alltrue([for i in var.caa_issuers : can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", i))])
    error_message = "every CAA issuer must be a bare lowercase domain without quotes (e.g. `amazon.com`)."
  }
}

variable "caa_ttl" {
  description = "TTL in seconds of the CAA record."
  type        = number
  default     = 300

  validation {
    condition     = var.caa_ttl >= 0 && floor(var.caa_ttl) == var.caa_ttl
    error_message = "caa_ttl must be a non-negative whole number of seconds."
  }
}

variable "name_tag" {
  description = "Value of the zone's `Name` tag. Left `null`, it falls back to `name`. Set it to an existing zone's current `Name` tag to adopt the zone without a tag change."
  type        = string
  default     = null
}

variable "component" {
  description = "Value of the `Component` tag on the zone."
  type        = string
  default     = "dns"

  validation {
    condition     = length(var.component) > 0
    error_message = "component must not be empty."
  }
}
