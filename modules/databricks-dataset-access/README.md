# databricks-dataset-access

Who may read one onboarded dataset (`databricks-dataset`). One instance per
dataset; each consumer is an edge both the producing project and the
consuming project declared (a handshake), so this module is applied by the
platform's access reconcile, not by either project. Applied through the
shared-objects host (`databricks-host-workspace`), like `databricks-dataset`.

Creates, per consumer:

- a binding of the dataset's isolated external location, and of its storage
  credential, to the consumer's workspace (a binding grants nothing);
- `USE_SCHEMA` on the dataset's schema and `READ_VOLUME` on its `files`
  volume for the consumer's users group.

Consumers read through the volume (`/Volumes/<catalog>/<schema>/files/`)
only: the location grants `READ_FILES` to `owner_group_name` alone. Each grant
set (location, schema, volume) is one authoritative `databricks_grants` that
always holds `owner_group_name`, so it is never empty and a grant made by hand
(`BROWSE` included) is removed. With no consumers, the three sets hold the
owner group alone and nothing is bound. The producer catalog's own binding and
`USE_CATALOG` are `databricks-producer-catalog-access`'s.

Without `schema_full_name` and `volume_full_name` (a dataset onboarded as a
location only), only the location's grants and the bindings are managed.

## Upgrading from READ_FILES

Before volumes, each consumer's users group held `READ_FILES` on the
location (`databricks_grants.this[0]`). A `moved` block makes that the
`location` grant set, updated in place to the owner group alone.

## Order

Each binding depends on every grant set, so Terraform creates the binding
last and destroys it first: a run that stops half way leaves less access,
never more. The host's own bindings belong to `databricks-dataset`.

Reading also needs the producer's bucket policy to name the dataset's role
and the consumer workspace's S3 endpoint to let it through (`databricks-dataset`'s
`endpoint_dataset`); this module only opens Unity Catalog's side.

## Validation

- `external_location_name`, `storage_credential_name`, `owner_group_name`:
  not empty.
- `schema_full_name` and `volume_full_name`: set together, as
  `<catalog>.<schema>` and `<catalog>.<schema>.<volume>`.
- `consumers`: keyed by kebab-case project, each with a positive
  `workspace_id` and a `users_group_name`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11 |
| databricks | >= 1.142, < 2.0 |

## Providers

| Name | Version |
| ---- | ------- |
| databricks | >= 1.142, < 2.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [databricks_grants.location](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/grants) | resource |
| [databricks_grants.schema](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/grants) | resource |
| [databricks_grants.volume](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/grants) | resource |
| [databricks_workspace_binding.consumer](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/workspace_binding) | resource |
| [databricks_workspace_binding.credential](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/workspace_binding) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| external\_location\_name | Name of the onboarded dataset's external location, the `external_location_name` output of `databricks-dataset`. | `string` | n/a | yes |
| owner\_group\_name | The group that owns the dataset's objects, the `admin_group_name` output of `databricks-metastore`. It alone holds READ FILES on the location, and it is in every grant set, so none is ever empty (an empty set would leave the securable unmanaged). | `string` | n/a | yes |
| storage\_credential\_name | Name of the dataset's storage credential, the `storage_credential_name` output of `databricks-dataset`. Each consumer workspace is bound to it so that Unity Catalog can use it there; a binding grants nothing. | `string` | n/a | yes |
| consumers | Workspaces that may read the dataset, keyed by project: each workspace's `workspace_id` and `users_group_name` (outputs of `databricks-workspace`). The location and credential are bound to each, and each users group gets `USE_SCHEMA` and `READ_VOLUME`. Every edge here is a handshake both the producer and the consumer declared. May be empty. | <pre>map(object({<br/>    workspace_id     = number<br/>    users_group_name = string<br/>  }))</pre> | `{}` | no |
| schema\_full\_name | `<catalog>.<schema>`, the dataset's schema (the `schema_full_name` output of `databricks-dataset`). With it, each consumer's users group gets USE SCHEMA. Set exactly when `volume_full_name` is; null for a dataset onboarded as a location only. | `string` | `null` | no |
| volume\_full\_name | `<catalog>.<schema>.files`, the dataset's external volume (the `volume_full_name` output of `databricks-dataset`). With it, each consumer's users group gets READ VOLUME. Set exactly when `schema_full_name` is. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| consumers | The projects whose workspaces are bound to the dataset and granted `READ_VOLUME` on it, sorted. |
<!-- END_TF_DOCS -->
