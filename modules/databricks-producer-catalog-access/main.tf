# Who may use one producer catalog (the data-access reconcile, one instance
# per producer catalog with a dataset ready). Per consumer with an agreed edge
# into any of the producer's datasets: a read-only binding of the catalog to
# its workspace, and USE CATALOG for its users group. The catalog binding is
# what keeps the producer's datasets out of every other workspace, whatever
# grants a person holds; inside it, each dataset is granted on its own
# (databricks-dataset-access), so a consumer lists only what it may read. The
# grant set is authoritative and always holds the owner group, so a grant made
# by hand (BROWSE included) is removed.

resource "databricks_grants" "catalog" {
  catalog = var.catalog_name

  grant {
    principal  = var.owner_group_name
    privileges = ["USE_CATALOG"]
  }

  dynamic "grant" {
    for_each = { for k, c in var.consumers : k => c.users_group_name }
    content {
      principal  = grant.value
      privileges = ["USE_CATALOG"]
    }
  }
}

# Depending on the grants makes Terraform create each binding last and destroy
# it first: a run that stops half way leaves less access, never more.
resource "databricks_workspace_binding" "consumer" {
  for_each = var.consumers

  workspace_id   = each.value.workspace_id
  securable_type = "catalog"
  securable_name = var.catalog_name
  binding_type   = "BINDING_TYPE_READ_ONLY"

  depends_on = [databricks_grants.catalog]
}
