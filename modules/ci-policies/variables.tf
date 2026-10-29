variable "name_root" {
  description = "Prefix of every policy name, in kebab-case. Policies are named `<name_root>-<project>-ci-<role>-<family>-<name>`."
  type        = string
  default     = "jwall-engineering"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name_root))
    error_message = "name_root must be kebab-case: lowercase letters, digits and single hyphens."
  }
}

variable "project" {
  description = "Project in kebab-case, for example `guitar` or `infra`. Used in policy names and as the `Project` tag value static-site policies are scoped to."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.project))
    error_message = "project must be kebab-case: lowercase letters, digits and single hyphens."
  }
}

variable "role" {
  description = "The CI role the policies are for: `plan`, `preview`, `apply`, `release` or `task`. It decides which policies may be requested."
  type        = string

  validation {
    condition     = contains(["plan", "preview", "apply", "release", "task"], var.role)
    error_message = "role must be one of: plan, preview, apply, release, task."
  }
}

variable "oidc_provider_arn" {
  description = "ARN of the account's GitHub Actions OIDC provider, which `foundation/read` may read."
  type        = string
}

variable "policies" {
  description = "Policies to create, from the catalog: `tfstate/read`, `tfstate/write`, `static-site/read`, `static-site/deploy`, `static-site/previews`, `foundation/read`, `foundation/manage`, `ecr/pull`, `ecr/push`, `container/read`, `container/manage`, `container/release`, `task/read`, `task/manage`, `task/launch`. Each role accepts only some of them; see the README."
  type        = set(string)

  validation {
    condition     = length(var.policies) > 0
    error_message = "policies must name at least one policy."
  }

  validation {
    condition     = alltrue([for p in var.policies : contains(keys(local.catalog), p)])
    error_message = "unknown policy in policies: ${join(", ", [for p in var.policies : p if !contains(keys(local.catalog), p)])}. Supported policies: ${join(", ", sort(keys(local.catalog)))}."
  }

  validation {
    condition     = alltrue([for p in var.policies : contains(local.allowed_classes[var.role], local.catalog[p]) if contains(keys(local.catalog), p)])
    error_message = "ci-${var.role}-role does not accept ${join(", ", [for p in var.policies : "${p} (a ${local.catalog[p]} policy)" if contains(keys(local.catalog), p) && !contains(local.allowed_classes[var.role], lookup(local.catalog, p, ""))])}. It accepts only ${join(" and ", local.allowed_classes[var.role])} policies: ${join(", ", sort([for p, c in local.catalog : p if contains(local.allowed_classes[var.role], c)]))}."
  }

  validation {
    condition     = !anytrue([for p in var.policies : startswith(p, "tfstate/")]) || var.policy_inputs.tfstate != null
    error_message = "tfstate/* policies require policy_inputs.tfstate."
  }

  validation {
    condition     = !anytrue([for p in var.policies : startswith(p, "static-site/")]) || var.policy_inputs.static_site != null
    error_message = "static-site/* policies require policy_inputs.static_site."
  }

  validation {
    condition     = !anytrue([for p in var.policies : contains(["static-site/read", "static-site/deploy"], p)]) || try(var.policy_inputs.static_site.zone_id, null) != null
    error_message = "static-site/read and static-site/deploy require policy_inputs.static_site.zone_id."
  }

  validation {
    condition     = !contains(var.policies, "static-site/deploy") || try(var.policy_inputs.static_site.record_names, null) != null
    error_message = "static-site/deploy requires policy_inputs.static_site.record_names."
  }

  validation {
    condition     = !anytrue([for p in var.policies : startswith(p, "foundation/")]) || var.policy_inputs.foundation != null
    error_message = "foundation/* policies require policy_inputs.foundation."
  }

  validation {
    condition     = !contains(var.policies, "task/launch") || try(length(var.policy_inputs.task.instance_types) > 0, false)
    error_message = "task/launch requires policy_inputs.task.instance_types."
  }

  validation {
    condition     = !anytrue([for p in var.policies : startswith(p, "ecr/")]) || var.policy_inputs.ecr != null
    error_message = "ecr/* policies require policy_inputs.ecr."
  }
}

variable "policy_inputs" {
  description = "Values the requested policies are built from, one optional section per policy family. `tfstate` takes `bucket_arn` and exactly one of `key` or `prefix`. `static_site` takes `bucket_arn`, plus `zone_id` for `read` and `deploy` and `record_names` for `deploy`. `foundation` takes `state_bucket_arn`, `hosted_zone_arn` and optionally `managed_bucket_patterns` and `attachable_policy_arns`. `ecr` takes `repository_arn`. `container` optionally takes `attachable_policy_arns` for `container/manage`; `task` takes `instance_types` for `task/launch`; the `container/*` policies are otherwise built from `project` alone."
  type = object({
    tfstate = optional(object({
      bucket_arn = string
      key        = optional(string)
      prefix     = optional(string)
    }))
    static_site = optional(object({
      bucket_arn   = string
      zone_id      = optional(string)
      record_names = optional(list(string))
    }))
    foundation = optional(object({
      state_bucket_arn        = string
      hosted_zone_arn         = string
      managed_bucket_patterns = optional(list(string))
      attachable_policy_arns  = optional(list(string))
    }))
    ecr = optional(object({
      repository_arn = string
    }))
    container = optional(object({
      attachable_policy_arns = optional(list(string))
    }))
    task = optional(object({
      instance_types = list(string)
    }))
  })
  default = {}
}
