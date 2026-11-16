output "consumers" {
  description = "The projects whose workspaces are bound to the dataset and granted `READ_FILES`, sorted."
  value       = sort(keys(var.consumers))
}
