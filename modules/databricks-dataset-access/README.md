# databricks-dataset-access

Binds one onboarded dataset (`databricks-dataset`) to the workspaces that may
read it, and grants their users groups `READ_FILES`. One instance per
dataset; each consumer is an edge both the producing project and the
consuming project declared (a handshake), so this module is applied by the
platform's access reconcile, not by either project. Applied through the
shared-objects host (`databricks-host-workspace`), like `databricks-dataset`.

Creates, per consumer:

- a binding of the dataset's isolated external location to the consumer's
  workspace;
- `READ_FILES` on the location for the consumer's users group, in one
  authoritative `databricks_grants` for the location: a grant made by hand is
  removed, and the owner (the metastore admin group) keeps every privilege.

With no consumers it creates nothing.

## Order

Each binding depends on the grants, so Terraform creates the binding last and
destroys it first: a run that stops half way leaves less access, never more.
The host's own binding belongs to `databricks-dataset`. Consumers reach the
files through the location, so the storage credential is not bound to them.

Reading also needs the producer's bucket policy to name the dataset's role
and the consumer workspace's S3 endpoint to let it through (`databricks-dataset`'s
`endpoint_dataset`); this module only opens Unity Catalog's side.

## Validation

- `external_location_name`: not empty.
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
| [databricks_grants.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/grants) | resource |
| [databricks_workspace_binding.consumer](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/workspace_binding) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| external\_location\_name | Name of the onboarded dataset's external location, the `external_location_name` output of `databricks-dataset`. | `string` | n/a | yes |
| consumers | Workspaces that may read the dataset, keyed by project: each workspace's `workspace_id` and `users_group_name` (outputs of `databricks-workspace`). The location is bound to each, and each users group gets `READ_FILES`. Every edge here is a handshake both the producer and the consumer declared. May be empty. | <pre>map(object({<br/>    workspace_id     = number<br/>    users_group_name = string<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| consumers | The projects whose workspaces are bound to the dataset and granted `READ_FILES`, sorted. |
<!-- END_TF_DOCS -->
