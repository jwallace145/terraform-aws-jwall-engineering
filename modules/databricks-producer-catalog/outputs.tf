output "catalog_name" {
  description = "The catalog's name: the producer with `-` replaced by `_`. It carries a dependency on the host's binding, so a schema created through the host comes after the binding and is destroyed before it."
  # Read from the host's binding, so a schema created through the host comes
  # after the binding and is destroyed before it: through an unbound workspace
  # nothing in an isolated catalog is visible, so a schema deleted in parallel
  # with the binding would fail, and every later apply with it.
  value = databricks_workspace_binding.host.securable_name
}
