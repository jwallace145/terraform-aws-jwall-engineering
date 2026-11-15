# databricks-audit-logs

Delivers Databricks account audit logs (JSON) to a private S3 bucket. Creates
the bucket (Block Public Access, SSE-S3 with a bucket key, versioning,
`BucketOwnerEnforced`, TLS-only policy), an IAM role that trusts Databricks'
AWS account only with `sts:ExternalId` equal to the Databricks account ID,
the Databricks credentials and storage configuration, and the
`databricks_mws_log_delivery` for `AUDIT_LOGS`.

**Scope.** Databricks (the delivery role) may write only under
`<prefix>/*` (`audit/*` by default); its bucket-level rights are
`s3:GetBucketLocation` and listing limited by an `s3:prefix` condition to the
prefix, as in Databricks' documented policy, with two departures that S3
requires of a bucket policy (it rejects the documented one as `MalformedPolicy`).
`s3:ListMultipartUploadParts` is object-level, so it is granted on the prefix's
objects, not the bucket ARN. `s3:ListBucketMultipartUploads` is dropped: the
documented statement conditions it on `s3:prefix`, a key that action does not
support, so it never granted anything. The role trusts Databricks'
`SaasUsageDeliveryRole` (not the account root) with the account ID as external ID. The bucket policy has no Deny besides non-TLS
requests, so the bucket can also host a future `events/` prefix written by
the account's own principals through their IAM policies.

**No `force_destroy`.** Destroying the stack fails while the bucket holds
objects, by design.

The module uses an **account-level** `databricks` provider
(`host = "https://accounts.cloud.databricks.com"`, authentication and account
ID from the environment) and the AWS provider; it configures neither. IAM is
eventually consistent: if the first apply fails validating the new role,
apply again.

## Known gaps

No policy in this module uses `Resource = "*"`.

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/databricks-audit-logs>

## Usage

```hcl
module "audit_logs" {
  source  = "jwallace145/jwall-engineering/aws//modules/databricks-audit-logs"
  version = "~> 0.18"

  account_id = "11111111-2222-3333-4444-555555555555"
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11 |
| aws | ~> 6.0 |
| databricks | >= 1.142, < 2.0 |
| time | ~> 0.13 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | ~> 6.0 |
| databricks | >= 1.142, < 2.0 |
| time | ~> 0.13 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_role.log_delivery](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.log_delivery](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [databricks_mws_credentials.log_delivery](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/mws_credentials) | resource |
| [databricks_mws_log_delivery.audit](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/mws_log_delivery) | resource |
| [databricks_mws_storage_configurations.log_delivery](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/mws_storage_configurations) | resource |
| [time_sleep.iam_propagation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| account\_id | Databricks account ID (a UUID). It is also the external ID the log delivery role requires from Databricks. | `string` | n/a | yes |
| bucket\_name | Name of the audit log bucket. | `string` | `"jwall-engineering-databricks-audit-logs"` | no |
| component | Value of the `Component` tag on the bucket and role. | `string` | `"databricks-audit-logs"` | no |
| prefix | Key prefix Databricks writes under. Databricks gets access to `<prefix>/*` only; other prefixes (for example `events/`) stay free for the account's own principals. | `string` | `"audit"` | no |
| role\_name | Name of the IAM role Databricks assumes to write the logs. | `string` | `"jwall-engineering-databricks-log-delivery"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| bucket\_arn | ARN of the audit log bucket, for IAM policies of principals that share it (for example under `events/`). |
| bucket\_name | Name of the audit log bucket. |
| log\_delivery\_config\_id | ID of the Databricks log delivery configuration. |
<!-- END_TF_DOCS -->
