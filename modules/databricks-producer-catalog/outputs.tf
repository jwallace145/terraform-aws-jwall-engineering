output "catalog_name" {
  description = "The catalog's name: the producer with `-` replaced by `_`."
  value       = databricks_catalog.this.name
}
