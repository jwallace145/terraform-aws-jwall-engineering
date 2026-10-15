# The context module creates no resources. It derives the naming and tagging
# conventions for a jwall-engineering project so that callers can feed `tags`
# into their provider's `default_tags` and reuse `name_prefix`/`bucket_name`.
# Because nothing here is a resource, every output is known at plan time.

locals {
  # Resource names are always prefixed with the jwall-engineering umbrella,
  # independent of the `organization` tag value.
  name_root = "jwall-engineering"

  required_tags = {
    Organization = var.organization
    Project      = var.project
    Environment  = var.environment
    Repository   = var.repository
    ManagedBy    = "terraform"
    Owner        = var.owner
  }

  # merge() lets later arguments win, so required tags override extra_tags.
  tags = merge(var.extra_tags, local.required_tags)

  name_prefix = "${local.name_root}-${var.project}-${var.environment}"
  bucket_name = "${local.name_root}-${var.project}"
}
