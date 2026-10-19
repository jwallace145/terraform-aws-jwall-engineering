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

variable "txt_records" {
  description = "Zone-level TXT records that belong to the zone owner rather than to a project, such as domain-verification tokens (`_github-pages-challenge-<user>`) or SPF. Keyed by the record name relative to the zone (`@` for the apex); each value is the list of strings for that record. Strings are quoted for Route 53 by the module, so pass them bare."
  type        = map(list(string))
  default     = {}

  validation {
    condition = alltrue([
      for k, _ in var.txt_records :
      k == "@" || (
        can(regex("^[a-z0-9_]([a-z0-9_-]{0,61}[a-z0-9_])?(\\.[a-z0-9_]([a-z0-9_-]{0,61}[a-z0-9_])?)*$", k))
        && k != var.name && !endswith(k, ".${var.name}")
      )
    ])
    error_message = "every txt_records key must be `@` or a lowercase record name relative to the zone (e.g. `_github-pages-challenge-jwallace145`), not a FQDN."
  }

  validation {
    condition     = alltrue([for _, values in var.txt_records : length(values) > 0])
    error_message = "every txt_records entry needs at least one string."
  }

  validation {
    condition     = alltrue([for _, values in var.txt_records : alltrue([for s in values : length(s) > 0 && length(s) <= 255 && !strcontains(s, "\"")])])
    error_message = "every TXT string must be 1 to 255 characters and contain no double quotes; the module adds the quotes Route 53 needs."
  }
}

variable "txt_ttl" {
  description = "TTL in seconds of the TXT records."
  type        = number
  default     = 300

  validation {
    condition     = var.txt_ttl >= 0 && floor(var.txt_ttl) == var.txt_ttl
    error_message = "txt_ttl must be a non-negative whole number of seconds."
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
