variable "name" {
  description = "Repository name, for example `jwall-engineering-sites`. Also the value of its `Name` tag."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*$", var.name)) && length(var.name) <= 256
    error_message = "name must be a valid ECR repository name: lowercase letters, digits and single `.`, `_`, `-` or `/` separators, at most 256 characters."
  }
}

variable "keep_release_images" {
  description = "How many images tagged with one of `release_tag_prefixes` to keep. Older ones expire."
  type        = number
  default     = 20

  validation {
    condition     = var.keep_release_images >= 1 && floor(var.keep_release_images) == var.keep_release_images
    error_message = "keep_release_images must be a positive integer."
  }
}

variable "expire_untagged_after_days" {
  description = "Untagged images (for example layers left behind by a failed push) expire this many days after being pushed."
  type        = number
  default     = 7

  validation {
    condition     = var.expire_untagged_after_days >= 1 && floor(var.expire_untagged_after_days) == var.expire_untagged_after_days
    error_message = "expire_untagged_after_days must be a positive integer."
  }
}

variable "release_tag_prefixes" {
  description = "Tag prefixes that identify release images, which `keep_release_images` applies to. Defaults to `v`, for tags like `v1.2.3`."
  type        = list(string)
  default     = ["v"]

  validation {
    condition     = length(var.release_tag_prefixes) > 0 && alltrue([for p in var.release_tag_prefixes : length(p) > 0])
    error_message = "release_tag_prefixes must contain at least one non-empty prefix."
  }
}

variable "component" {
  description = "Value of the `Component` tag on the repository."
  type        = string
  default     = "ecr-repository"

  validation {
    condition     = length(var.component) > 0
    error_message = "component must not be empty."
  }
}
