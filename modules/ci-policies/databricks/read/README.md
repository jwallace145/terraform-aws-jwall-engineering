# databricks/read

Read what a Databricks workspace project's stacks need for `terraform plan`
and refresh, beyond [`compute/read`](../../compute/read): the configuration of
the root bucket `<p>-databricks-root` and the catalog bucket
`<p>-databricks-catalog` (with `<p>` = `<name_root>-<project>`), and the
Databricks credential in one SSM parameter. It also appends to the project's
event log. Class: **read**.

EC2 describes and the `<name_root>-<project>-*` roles, which include
`<p>-databricks-cross-account` and `<p>-databricks-uc`, are read through
`compute/read`, which the plan and apply roles of such a project also hold.
Databricks API calls need no AWS permission.

Part of the [`ci-policies`](../..) catalog. Request it from a CI role module
with `policies = ["databricks/read"]` and
`policy_inputs = { databricks = { secret_parameter_arn, events_object_arn } }`;
it is not meant to be called directly.

## How it is scoped

- **Buckets by name, never their objects.** Configuration reads on the two
  bucket ARNs. `s3:ListBucket` is what refresh's `HeadBucket` needs; it lists
  object keys, not their contents. The catalog bucket's own policy denies
  every object read except to the Unity Catalog role.
- **One parameter.** `ssm:GetParameter` on `secret_parameter_arn` only, which
  must name one parameter (no wildcard). `kms:Decrypt` is limited with
  `kms:ViaService = ssm.us-east-1.amazonaws.com` and
  `kms:EncryptionContext:PARAMETER_ARN = secret_parameter_arn`: Parameter
  Store encrypts a SecureString with its ARN as encryption context, so the
  grant decrypts that parameter and nothing else, under any key in the
  account.
- **One quota.** `servicequotas:GetServiceQuota` on the `quota` resource
  `arn:aws:servicequotas:<region>:<account>:ec2/L-1216C47A` (Running
  On-Demand Standard instances vCPUs) only, for the infra CLI's vCPU
  headroom check. The action supports resource-level permissions, so there is
  no wildcard.
- **Event log, append-only.** `s3:PutObject` on `events_object_arn`, which
  must be `arn:aws:s3:::<audit bucket>/events/project=<project>/*`. No read,
  no list, no delete. It is the one write in this read policy, so the plan
  role, which trusts `pull_request`, can record events too.

## Known gaps

None: no statement uses `Resource = "*"`.


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
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| events\_object\_arn | Object ARN pattern of the project's event log, `arn:aws:s3:::jwall-engineering-databricks-audit-logs/events/project=<project>/*`. The policy may only put objects there: no read, no delete. | `string` | n/a | yes |
| name | Name of the managed policy, for example `jwall-engineering-databricks-poc-ci-apply-databricks-read`. | `string` | n/a | yes |
| project | Project name in kebab-case, for example `databricks-poc`. Bucket names are built from `<name_root>-<project>` and EC2 is scoped by the `Project` tag. | `string` | n/a | yes |
| secret\_parameter\_arn | ARN of the one SSM SecureString parameter holding the Databricks credential, for example `arn:aws:ssm:us-east-1:123456789012:parameter/jwall-engineering/databricks-poc/databricks`. The policy may read and decrypt this parameter only. | `string` | n/a | yes |
| name\_root | Prefix of resource names, in kebab-case. With `<p>` = `<name_root>-<project>`, the buckets are `<p>-databricks-root` and `<p>-databricks-catalog`. | `string` | `"jwall-engineering"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the managed policy. |
| name | Name of the managed policy. |
| policy | The policy document as a JSON string. |
<!-- END_TF_DOCS -->