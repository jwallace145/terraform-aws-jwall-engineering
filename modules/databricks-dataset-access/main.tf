# Consumers read files, nothing more: the location is read-only whatever the
# grant, and the owner (the metastore admin group) keeps every privilege.
# Authoritative for the location, so a grant made by hand is removed.
resource "databricks_grants" "this" {
  # The provider needs at least one grant block.
  count = length(var.consumers) > 0 ? 1 : 0

  external_location = var.external_location_name

  dynamic "grant" {
    for_each = { for k, c in var.consumers : k => c.users_group_name }
    content {
      principal  = grant.value
      privileges = ["READ_FILES"]
    }
  }
}

# Binding a consumer's workspace is what lets it use the isolated location at
# all. Depending on the grants makes Terraform create each binding last and
# destroy it first, so a run that stops half way leaves less access, never
# more. The host's own binding is databricks-dataset's; consumers reach the
# files through the location, so the storage credential is not bound to them.
resource "databricks_workspace_binding" "consumer" {
  for_each = var.consumers

  workspace_id   = each.value.workspace_id
  securable_type = "external_location"
  securable_name = var.external_location_name

  depends_on = [databricks_grants.this]
}
