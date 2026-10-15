# foundation/manage

Write access for the foundation stack: configure the state bucket, manage
buckets matching `managed_bucket_patterns` (never their objects), manage
`<name_root>-*` roles and policies with an `ArnLike` allow-list on attaching
managed policies, and change records in the hosted zone. Grants no reads
beyond what managing requires; pair it with `foundation/read`. See the
known limitation in the [`ci-policies`](../..) README. Class: **write**.

Part of the [`ci-policies`](../..) catalog. Request it from a CI role module
with `policies = ["foundation/manage"]`; it is not meant to be called directly.

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
| hosted\_zone\_arn | ARN of the hosted zone the foundation stack manages (output `arn` of `hosted-zone`). | `string` | n/a | yes |
| name | Name of the managed policy, for example `jwall-engineering-infra-ci-apply-foundation-manage`. | `string` | n/a | yes |
| state\_bucket\_arn | ARN of the Terraform state bucket (output `arn` of `tfstate-bucket`). | `string` | n/a | yes |
| attachable\_policy\_arns | Managed policy ARN patterns the policy allows attaching with `iam:AttachRolePolicy` (an `ArnLike` allow-list). Defaults to the account's `<name_root>-*` customer-managed policies, which include every policy `ci-policies` creates. | `list(string)` | `null` | no |
| managed\_bucket\_patterns | Bucket name patterns the foundation stack manages. Defaults to `["<name_root>-*"]`, which covers every `site-bucket`. The policies reach the buckets themselves, never their objects. | `list(string)` | `null` | no |
| name\_root | Prefix of every role, policy and bucket the foundation stack manages, in kebab-case. | `string` | `"jwall-engineering"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the managed policy. |
| name | Name of the managed policy. |
| policy | The policy document as a JSON string. |
<!-- END_TF_DOCS -->
