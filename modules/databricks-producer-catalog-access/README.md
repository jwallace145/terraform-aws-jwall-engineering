# databricks-producer-catalog-access

Who may use one producer catalog (`databricks-producer-catalog`). One instance
per producer catalog; each consumer has at least one agreed edge (a handshake
both the producing and the consuming project declared) into the producer's
datasets, so this module is applied by the platform's access reconcile, not
by either project. Applied through the shared-objects host.

Creates, per consumer:

- a read-only binding (`BINDING_TYPE_READ_ONLY`) of the catalog to the
  consumer's workspace: the catalog is invisible and inaccessible in every
  workspace it is not bound to, whatever grants a person holds;
- `USE_CATALOG` for the consumer's users group, in one authoritative grant set
  that always holds `owner_group_name`, so a grant made by hand (`BROWSE`
  included) is removed.

Each dataset in the catalog is granted on its own (`USE_SCHEMA` and
`READ_VOLUME`, `databricks-dataset-access`), so a consumer's users list and
read only the datasets shared with their workspace. With no consumers, the
owner group alone holds `USE_CATALOG` and nothing is bound.

## Order

Each binding depends on the grants, so Terraform creates the binding last and
destroys it first: a run that stops half way leaves less access, never more.
The host's read-write binding is `databricks-producer-catalog`'s.

## Usage

See [examples/basic](examples/basic/main.tf).

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
| [databricks_grants.catalog](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/grants) | resource |
| [databricks_workspace_binding.consumer](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/workspace_binding) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| catalog\_name | The producer's catalog, the `catalog_name` output of `databricks-producer-catalog`, for example `braveheart_selfplay`. | `string` | n/a | yes |
| owner\_group\_name | The group that owns the catalog, the `admin_group_name` output of `databricks-metastore`. It is always in the catalog's grant set, so the set is never empty (an empty set would leave the catalog's grants unmanaged). | `string` | n/a | yes |
| consumers | Workspaces with at least one agreed edge into this producer's datasets, keyed by project: each workspace's `workspace_id` and `users_group_name` (outputs of `databricks-workspace`). The catalog is bound read-only to each, and each users group gets `USE_CATALOG`. May be empty. | <pre>map(object({<br/>    workspace_id     = number<br/>    users_group_name = string<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| consumers | The projects whose workspaces are bound to the catalog and granted `USE_CATALOG`, sorted. |
<!-- END_TF_DOCS -->
