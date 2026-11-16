# One isolated catalog per dataset producer: every dataset the producer has
# onboarded becomes a schema in it (databricks-dataset), holding an external
# volume. The platform owns it; the producer is its logical owner, in its name
# and properties. Bound read-write to the host only, through which the
# platform manages it; consumers are bound read-only, and granted USE CATALOG,
# by databricks-producer-catalog-access, which also owns the catalog's grants.

locals {
  catalog_name = replace(var.producer, "-", "_")
}

resource "databricks_catalog" "this" {
  name           = local.catalog_name
  comment        = "Datasets produced by ${var.producer}, shared read-only through agreed handshakes; managed by Terraform"
  storage_root   = "${var.storage_url}/${local.catalog_name}"
  isolation_mode = "ISOLATED"
  owner          = var.owner_group_name
  properties     = merge(var.properties, { producer = var.producer })

  # It holds only external volumes, whose files are never deleted with it.
  force_destroy = true
}

resource "databricks_workspace_binding" "host" {
  workspace_id   = var.host_workspace_id
  securable_type = "catalog"
  securable_name = databricks_catalog.this.name
  binding_type   = "BINDING_TYPE_READ_WRITE"
}
