output "consumers" {
  description = "The projects whose workspaces are bound to the dataset and granted `READ_VOLUME` on it, sorted."
  value       = sort(keys(var.consumers))
}
