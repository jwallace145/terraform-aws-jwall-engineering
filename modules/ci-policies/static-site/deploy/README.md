# static-site/deploy

Write access to one project's static site: create and manage its CloudFront
distributions, functions and ACM certificates (by `Project` tag), change only
its `record_names` and their ACM validation records, and publish content under
`prod/` and `dev/`. Grants no reads; pair it with `static-site/read`.
Class: **write**.

Part of the [`ci-policies`](../..) catalog. Request it from a CI role module
with `policies = ["static-site/deploy"]`; it is not meant to be called directly.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11 |
| aws | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| bucket\_arn | ARN of the project's site bucket (output `arn` of the `site-bucket` module). | `string` | n/a | yes |
| name | Name of the managed policy, for example `jwall-engineering-guitar-ci-apply-static-site-deploy`. | `string` | n/a | yes |
| project | Project name in kebab-case. Tag-scoped statements require `Project = <project>`. | `string` | n/a | yes |
| record\_names | FQDNs the project may manage in the hosted zone, including the wildcard preview name (for example `["guitar.example.com", "dev.guitar.example.com", "*.preview.guitar.example.com"]`). ACM validation CNAMEs for these names are allowed automatically. | `list(string)` | n/a | yes |
| zone\_id | Route 53 hosted zone ID the project's records live in. | `string` | n/a | yes |
| name\_root | Prefix of resource names, in kebab-case. CloudFront Functions are scoped to `<name_root>-<project>-*`. | `string` | `"jwall-engineering"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the managed policy. |
| name | Name of the managed policy. |
| policy | The policy document as a JSON string. |
<!-- END_TF_DOCS -->
