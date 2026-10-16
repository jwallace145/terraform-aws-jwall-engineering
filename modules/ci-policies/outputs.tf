locals {
  # Requested policy name -> its module instance. Keys come from var.policies,
  # so they are known at plan time even when the ARNs are not.
  created = merge(
    { for m in module.tfstate_read : "tfstate/read" => m },
    { for m in module.tfstate_write : "tfstate/write" => m },
    { for m in module.static_site_read : "static-site/read" => m },
    { for m in module.static_site_deploy : "static-site/deploy" => m },
    { for m in module.static_site_previews : "static-site/previews" => m },
    { for m in module.foundation_read : "foundation/read" => m },
    { for m in module.foundation_manage : "foundation/manage" => m },
    { for m in module.ecr_pull : "ecr/pull" => m },
    { for m in module.ecr_push : "ecr/push" => m },
  )
}

output "arns" {
  description = "Map of requested policy (for example `static-site/read`) to the ARN of the managed policy created for it."
  value       = { for p, m in local.created : p => m.arn }
}

output "names" {
  description = "Map of requested policy to the name of the managed policy created for it."
  value       = { for p, m in local.created : p => m.name }
}

output "documents" {
  description = "Map of requested policy to its policy document as a JSON string."
  value       = { for p, m in local.created : p => m.policy }
}
