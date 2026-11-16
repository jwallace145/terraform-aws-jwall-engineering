# databricks-dataset

Onboards one S3 dataset to the platform: **one** read-only Unity Catalog
storage credential and external location, owned by the platform, that any
number of Databricks workspaces can later be bound to. Unity Catalog refuses
overlapping external locations in a metastore, so a dataset is onboarded
exactly once, here; who may read it is `databricks-dataset-access`'s job.
Applied through the shared-objects host (`databricks-host-workspace`): the
module's workspace-level `databricks` provider points at the host's
`workspace_url`.

Creates, all named `name` (for example
`jwall-engineering-ds-braveheart-selfplay-positions`):

- an IAM role trusting Databricks' Unity Catalog master role with the storage
  credential's external ID and itself (self-assuming), as
  `databricks-catalog`'s role does;
- an isolated, read-only storage credential for it, owned by
  `owner_group_name` (the metastore admin group);
- an isolated, read-only external location at `s3://<bucket>/<prefix>` (no
  trailing slash), owned by `owner_group_name`;
- the host's bindings to both, and nothing else: no consumer binding and no
  grant.

## Onboarding grants no access

The role's own IAM policy holds only `s3:GetBucketLocation` on the bucket
(which reveals no data and Databricks needs) and its self-assume. It can read
and list the dataset only once the dataset's bucket policy names it as a
reader (`dataset-bucket`'s `reader_role_arns`), which in the same account is
enough on its own. So an onboarded dataset nobody has agreed to share can be
read by nobody, and the project that owns the data holds the switch.

A consumer then needs three things beyond onboarding:
`databricks-dataset-access` binding its workspace and granting its users
group `READ_FILES`, the producer's bucket policy naming the role, and its
workspace's S3 endpoint letting the role through (pass `endpoint_dataset` to
its `databricks-workspace` `read_only_datasets`).

The location is created with `skip_validation = true`. Validation would check
that the role can read and list, which only the producer's bucket policy
allows, and that is applied by another stack on its own schedule. Until the
producer names the role, reads fail with access denied and nothing else
changes.

## Validation

- `name`: kebab-case, at most 64 characters (IAM role names).
- `bucket`: an S3 bucket name. `prefix`: one or more segments ending in `/`,
  no leading `/`, no `*`.
- `host_workspace_id`: a positive integer.

## In the producer's catalog

With `catalog_name` and `schema_name` (the producer's catalog from
`databricks-producer-catalog`), the dataset is also a schema in that catalog
holding one external volume, `files`, at the location's URL: consumers find it
in Catalog Explorer and read `/Volumes/<catalog>/<schema>/files/` (outputs
`schema_full_name`, `volume_full_name`, `volume_path`). An external volume's
files are never deleted with it.

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
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [databricks_external_location.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/external_location) | resource |
| [databricks_schema.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/schema) | resource |
| [databricks_storage_credential.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/storage_credential) | resource |
| [databricks_volume.files](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/volume) | resource |
| [databricks_workspace_binding.credential](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/workspace_binding) | resource |
| [databricks_workspace_binding.location](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/workspace_binding) | resource |
| [time_sleep.role_propagation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [databricks_aws_unity_catalog_assume_role_policy.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/aws_unity_catalog_assume_role_policy) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| bucket | The dataset's S3 bucket, in this account and region, for example `jwall-engineering-braveheart-selfplay-positions`. | `string` | n/a | yes |
| host\_workspace\_id | Numeric ID of the shared-objects host, the `workspace_id` output of `databricks-host-workspace`: the workspace this module's `databricks` provider points at. | `number` | n/a | yes |
| name | The dataset's platform name, in kebab-case: the IAM role, the storage credential and the external location all take it, for example `jwall-engineering-ds-braveheart-selfplay-positions` (`<organization>-ds-<owner>-<dataset>`). | `string` | n/a | yes |
| owner\_group\_name | Account group that owns the storage credential and external location, the `admin_group_name` output of `databricks-metastore`: no project owns an onboarded dataset's Databricks objects. | `string` | n/a | yes |
| prefix | The prefix onboarded, one or more path segments ending in `/` with no leading `/`, for example `data/`. The dataset's bucket-policy readers grant must cover it. | `string` | n/a | yes |
| catalog\_name | The producer's catalog, the `catalog_name` output of `databricks-producer-catalog`. With it the dataset becomes a schema there holding an external volume `files` at the location's URL, which consumers find in Catalog Explorer. Null onboards the location only. | `string` | `null` | no |
| component | Value of the `Component` tag on every AWS resource. | `string` | `"databricks-dataset"` | no |
| schema\_name | The dataset's schema in `catalog_name`: the dataset's name with `-` replaced by `_`, for example `positions`. Set exactly when `catalog_name` is. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| endpoint\_dataset | The entry each consumer passes to `databricks-workspace`'s `read_only_datasets`. Built from names, so it is known before the role exists. |
| external\_location\_name | Name of the read-only external location (the dataset's name): what `databricks-dataset-access` binds and grants. |
| role\_arn | ARN of the dataset's IAM role, which reads only once the dataset's bucket policy names it as a reader. |
| schema\_full\_name | `<catalog>.<schema>`, the dataset's schema; null without `catalog_name`. Built from names, so it is known before the schema exists. |
| storage\_credential\_name | Name of the read-only storage credential (the dataset's name). |
| url | The location's URL, `s3://<bucket>/<prefix>` without the trailing slash. |
| volume\_full\_name | `<catalog>.<schema>.files`, the dataset's external volume; null without `catalog_name`. |
| volume\_path | `/Volumes/<catalog>/<schema>/files`, the path consumers read; null without `catalog_name`. |
<!-- END_TF_DOCS -->
