# databricks-shared-dataset

One S3 dataset shared, read-only, with any number of Databricks workspaces
through **one** Unity Catalog external location. Unity Catalog refuses
overlapping external locations in a metastore, so a dataset prefix is
registered exactly once, here, and every consumer is bound to that location
rather than creating its own. Applied through the shared-objects host
(`databricks-host-workspace`): the module's workspace-level `databricks`
provider points at the host's `workspace_url`.

Creates:

- the share role `<name_root>-<name>-databricks-share`, trusting Databricks'
  Unity Catalog master role with the storage credential's external ID and
  itself (self-assuming), as `databricks-catalog`'s role does;
- an isolated, read-only storage credential for it, owned by
  `owner_group_name` (the metastore admin group) and bound to the host only;
- an isolated, read-only external location `<name_root>-<name>` at
  `s3://<bucket>/<prefix>` (no trailing slash), owned by `owner_group_name`,
  bound to the host and to every consumer workspace;
- `READ_FILES` on the location for every consumer's users group, and nothing
  else.

## Who grants access

The share role's own IAM policy holds only `s3:GetBucketLocation` on the
bucket (which reveals no data and Databricks needs) and its self-assume. It
can read and list the dataset only because the dataset's bucket policy names
it as a reader (`dataset-bucket`'s `reader_role_arns`), which in the same
account is enough on its own. So the project that owns the data grants access
to every consumer at once, in its own configuration, and can revoke it.
Consumers are added or removed here, by binding and grant.

A consumer also needs its workspace's S3 endpoint to let the share role
through: pass `endpoint_dataset` to that workspace's `databricks-workspace`
`read_only_datasets`, under the dataset's name.

The location is created with `skip_validation = true`. Validation would check
that the role can read and list, which only the producer's bucket policy
allows, and that is applied by another stack on its own schedule. Until the
producer names the role, reads fail with access denied and nothing else
changes.

## Validation

- `name`: kebab-case; `<name_root>-<name>-databricks-share` at most 64
  characters (29 with the default `name_root`).
- `bucket`: an S3 bucket name. `prefix`: one or more segments ending in `/`,
  no leading `/`, no `*`.
- `host_workspace_id`: a positive integer.
- `consumers`: keyed by kebab-case project, each with a positive
  `workspace_id` and a `users_group_name`; `host` is reserved.

## Known gaps

- Binding a location created through a serverless host to classic consumer
  workspaces is expected to work (bindings are metastore-level) and is
  confirmed by the first live apply.
- Serverless compute in a consumer workspace does not traverse its S3
  endpoint, so the endpoint statement does not apply to it; the bucket policy
  and Unity Catalog grants still do.

## Usage

```hcl
module "nnue" {
  source = "jwallace145/jwall-engineering/aws//modules/databricks-shared-dataset"

  name              = "rusty-chess-nnue"
  bucket            = "jwall-engineering-rusty-chess-nnue"
  prefix            = "data/"
  host_workspace_id = module.host.workspace_id
  owner_group_name  = module.metastore.admin_group_name

  consumers = {
    braveheart = { workspace_id = 1234567890123456, users_group_name = "braveheart-workspace-users" }
  }
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
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [databricks_external_location.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/external_location) | resource |
| [databricks_grants.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/grants) | resource |
| [databricks_storage_credential.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/storage_credential) | resource |
| [databricks_workspace_binding.credential](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/workspace_binding) | resource |
| [databricks_workspace_binding.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/workspace_binding) | resource |
| [time_sleep.role_propagation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [databricks_aws_unity_catalog_assume_role_policy.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/aws_unity_catalog_assume_role_policy) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| bucket | The dataset's S3 bucket, in this account and region, for example `jwall-engineering-rusty-chess-nnue`. | `string` | n/a | yes |
| host\_workspace\_id | Numeric ID of the shared-objects host, the `workspace_id` output of `databricks-host-workspace`: the workspace this module's `databricks` provider points at. | `number` | n/a | yes |
| name | The dataset's name in kebab-case, unique in the account, for example `rusty-chess-nnue` (the producing project and its dataset). | `string` | n/a | yes |
| owner\_group\_name | Account group that owns the storage credential and external location, the `admin_group_name` output of `databricks-metastore`: no project owns a shared dataset's Databricks objects. | `string` | n/a | yes |
| prefix | The prefix shared, one or more path segments ending in `/` with no leading `/`, for example `data/`. The dataset's readers grant must cover it. | `string` | n/a | yes |
| component | Value of the `Component` tag on every AWS resource. | `string` | `"databricks-shared-dataset"` | no |
| consumers | Workspaces that may read the dataset, keyed by project: each workspace's `workspace_id` and `users_group_name` (outputs of `databricks-workspace`). The location is bound to each and its users group gets `READ_FILES`. Each consumer must also pass `endpoint_dataset` to its `databricks-workspace` (`read_only_datasets`). May be empty. | <pre>map(object({<br/>    workspace_id     = number<br/>    users_group_name = string<br/>  }))</pre> | `{}` | no |
| name\_root | Prefix of resource names, in kebab-case. The role and storage credential are `<name_root>-<name>-databricks-share`, the external location `<name_root>-<name>`. | `string` | `"jwall-engineering"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| endpoint\_dataset | The entry each consumer passes to `databricks-workspace`'s `read_only_datasets` under the dataset's name. Built from names, so it is known before the role exists. |
| external\_location\_name | Name of the shared, read-only external location (`<name_root>-<name>`). |
| role\_arn | ARN of the dataset's Unity Catalog role (`<name_root>-<name>-databricks-share`): the one principal the producer names as a reader of the dataset. |
| url | URL of the external location, `s3://<bucket>/<prefix>` without the trailing slash: the path consumers read. |
<!-- END_TF_DOCS -->

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/databricks-shared-dataset>
