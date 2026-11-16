# databricks-catalog-storage

Managed storage for the platform's own catalogs: one producer catalog per
dataset producer (`databricks-producer-catalog`). The metastore deliberately
has no storage root, so every catalog needs a managed location; these
catalogs share one bucket, with a prefix each (`<url>/<catalog>`). Nothing is
ever written here: the catalogs hold only external volumes, consumers are
bound read-only, and nobody is granted a `CREATE` privilege. Applied through
the shared-objects host (`databricks-host-workspace`).

Creates, all named `name` (for example `jwall-engineering-dataset-catalogs`):

- an S3 bucket, private, SSE-S3, owner-enforced, whose policy denies object
  reads and writes to every principal but the Unity Catalog role (the apply
  role may list and delete, never read or put), as `databricks-catalog`'s;
- a self-assuming Unity Catalog IAM role with Databricks' managed-storage
  policy for the bucket;
- an isolated storage credential and an external location at
  `s3://<name>/managed`, owned by `owner_group_name`, bound to the host only,
  with an authoritative grant set (`ALL_PRIVILEGES` for `owner_group_name`).

## Usage

See [examples/basic](examples/basic/main.tf).

## Outputs

`external_location_name`, `url` (each catalog's `storage_root` is
`<url>/<catalog>`), `storage_credential_name`, `bucket_name`, `uc_role_arn`.

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
| [aws_iam_role.uc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.uc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [databricks_external_location.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/external_location) | resource |
| [databricks_grants.location](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/grants) | resource |
| [databricks_storage_credential.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/storage_credential) | resource |
| [databricks_workspace_binding.credential](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/workspace_binding) | resource |
| [databricks_workspace_binding.location](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/workspace_binding) | resource |
| [time_sleep.uc_role_propagation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [databricks_aws_unity_catalog_assume_role_policy.uc](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/aws_unity_catalog_assume_role_policy) | data source |
| [databricks_aws_unity_catalog_policy.uc](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/aws_unity_catalog_policy) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| apply\_role\_arn | ARN of the CI apply role. The bucket policy lets it list and delete objects (so a destroy can empty the bucket) and denies it reading or writing them. | `string` | n/a | yes |
| host\_workspace\_id | Numeric ID of the shared-objects host, the `workspace_id` output of `databricks-host-workspace`: the workspace this module's `databricks` provider points at, and the only one the credential and location are bound to. | `number` | n/a | yes |
| name | Name of the bucket, the Unity Catalog IAM role, the storage credential and the external location, in kebab-case, for example `jwall-engineering-dataset-catalogs`. | `string` | n/a | yes |
| owner\_group\_name | Account group that owns the credential and location and holds `ALL_PRIVILEGES` on the location: the `admin_group_name` output of `databricks-metastore`. | `string` | n/a | yes |
| component | The `Component` tag of the bucket and the role. | `string` | `"dataset-catalogs"` | no |
| tags | Tags for the bucket and the role, on top of the provider's default tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| bucket\_name | Name of the bucket. |
| external\_location\_name | Name of the external location the catalogs' managed locations sit under. |
| storage\_credential\_name | Name of the storage credential. |
| uc\_role\_arn | ARN of the Unity Catalog role, the only principal that may read or write the bucket's objects. |
| url | The location's URL, `s3://<name>/managed`: each catalog's `storage_root` is `<url>/<catalog>`. It carries a dependency on the location, its host binding and its grants, so a catalog using it is created after them and destroyed before them. |
<!-- END_TF_DOCS -->
