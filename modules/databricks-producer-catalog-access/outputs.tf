output "consumers" {
  description = "The projects whose workspaces are bound to the catalog and granted `USE_CATALOG`, sorted."
  value       = sort(keys(var.consumers))
}
