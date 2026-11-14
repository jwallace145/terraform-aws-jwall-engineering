# databricks-workspace-config

Governance configuration of one Databricks workspace: the **workspace stack**'s
compute policies and settings. Creates:

- one `databricks_cluster_policy` per entry of `compute_policies`, named after
  its key. The policy `definition` is the caller's rules merged with a `fixed`
  rule for every `fixed_tags` entry (`custom_tags.<key>`), so every cluster
  created through a policy carries the platform's tags and the caller cannot
  override them;
- `CAN_USE` on every policy for the users group (`users_group_name`), and
  nothing else;
- `databricks_entitlements` for the users group and, by default, for the
  built-in `users` group (Databricks grants it unrestricted cluster creation
  and every user belongs to it), set explicitly (see "Entitlements");
- with `enable_system_schemas`, one `databricks_system_schema` per entry of
  `system_schemas` (default `access`, `billing`, `compute`, `lakeflow`,
  `query`, `storage`). System schemas are metastore-wide: enable them in the
  one governance workspace only. A precondition checks that the workspace's
  current metastore is `metastore_id`;
- workspace settings: `databricks_disable_legacy_dbfs_setting` (true),
  `databricks_disable_legacy_access_setting` (true) and
  `databricks_workspace_conf` with `maxTokenLifetimeDays` (default 90).

## Workspace stack

The module needs a **workspace-level** `databricks` provider (`host` = the
account stack's `workspace_url` output) and configures none. It is applied
after `databricks-workspace`, and takes that module's `users_group_name` output.
The users group is looked up by name (`databricks_group`), so it must already
be assigned to the workspace.

## Compute policies and what they do not cover

- With `allow_cluster_create = false` users cannot create unrestricted
  clusters, but they **can** still create clusters through a policy they hold
  `CAN_USE` on. That is how Databricks policies work, and the intent here: the
  only clusters users can create are policy-bound ones.
- Policies govern **classic clusters only**. **Serverless compute stays
  enabled** (an owner decision): its cost and tags are not controlled by these
  policies, and no setting here disables it. This is an accepted, documented
  gap.
- Policy rules for node types, sizes and runtimes are the caller's; the module
  enforces only the `fixed_tags` and the presence of `autotermination_minutes`.

## Entitlements

`databricks_entitlements` replaces the principal's whole entitlement set on
every apply: the provider sends only the attributes that are `true` (all
default to `false`). Each entitlement is therefore stated:

| Entitlement | Value | Why |
| --- | --- | --- |
| `workspace_access` | `true` | users keep the workspace UI; leaving it unset would remove it |
| `databricks_sql_access` | `true` | users keep Databricks SQL and SQL warehouses; leaving it unset would remove it |
| `allow_cluster_create` | `false` | no unrestricted clusters; policies are the way to create them |
| `allow_instance_pool_create` | `false` | users do not create instance pools |
| `workspace_consume` | unset | conflicts with the two access entitlements above, which stay on |

Destroying the resource removes these entitlements from the group.

## Validation

- `compute_policies`: keys kebab-case (`^[a-z0-9]+(-[a-z0-9]+)*$`); no
  definition sets `custom_tags.*` (the platform owns them); every definition
  sets `autotermination_minutes`.
- `fixed_tags`: no empty keys or values; must contain `Project`,
  `Environment`, `CostCenter`, `Workspace`, `Owner` and `ManagedBy`, and no key
  Databricks reserves (`Vendor`, `Creator`, `ClusterName`, `ClusterId`, `Name`).
- `metastore_id`: a UUID. `system_schemas`: lowercase schema names.
- `max_token_lifetime_days`: a positive whole number.

## Known gaps

- Serverless compute is not governed (above).
- The settings resources, `databricks_workspace_conf` included, affect the
  whole workspace and are not scoped to the users group.
- The module has no `Resource = "*"` IAM statements and creates no AWS
  resources, so there are no `Name`/`Component` tags to apply.

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/databricks-workspace-config>

## Usage

```hcl
module "workspace_config" {
  source  = "jwallace145/jwall-engineering/aws//modules/databricks-workspace-config"
  version = "~> 0.18"

  users_group_name = var.users_group_name # databricks-workspace's users_group_name
  metastore_id     = var.metastore_id

  fixed_tags = {
    Project     = "databricks-poc"
    Environment = "dev"
    CostCenter  = "cc-0000"
    Workspace   = "databricks-poc-dev"
    Owner       = "team-a"
    ManagedBy   = "terraform"
  }

  compute_policies = {
    team-a-jobs = {
      description = "Small autoscaling jobs compute"
      definition = {
        autotermination_minutes = { type = "fixed", value = 30, hidden = true }
        node_type_id            = { type = "allowlist", values = ["m5.xlarge", "m5.2xlarge"] }
      }
    }
  }
}
```

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
| [databricks_cluster_policy.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/cluster_policy) | resource |
| [databricks_disable_legacy_access_setting.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/disable_legacy_access_setting) | resource |
| [databricks_disable_legacy_dbfs_setting.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/disable_legacy_dbfs_setting) | resource |
| [databricks_entitlements.builtin_users](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/entitlements) | resource |
| [databricks_entitlements.users](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/entitlements) | resource |
| [databricks_permissions.policy](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/permissions) | resource |
| [databricks_system_schema.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/system_schema) | resource |
| [databricks_workspace_conf.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/workspace_conf) | resource |
| [databricks_current_metastore.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/current_metastore) | data source |
| [databricks_group.builtin_users](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/group) | data source |
| [databricks_group.users](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/group) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| compute\_policies | Platform-owned cluster policies, keyed by policy name (lowercase kebab-case, for example `team-a-jobs`). `definition` is the policy rules as an object (Databricks' policy definition language); the module adds a `fixed` rule for every entry of `fixed_tags` under `custom_tags.<key>`. Each definition must set `autotermination_minutes` and must not set `custom_tags.*` itself. The CLI passes only this project's policies. | <pre>map(object({<br/>    description = string<br/>    definition  = any<br/>  }))</pre> | n/a | yes |
| fixed\_tags | Tags pinned on every cluster created through a platform policy, as `custom_tags.<key>` rules of type `fixed` (for example `CostCenter`, `Project`). Must contain `Project`, `Environment`, `CostCenter`, `Workspace`, `Owner` and `ManagedBy` (the same governance tags as `databricks-workspace`'s `tags`), and no key Databricks reserves (`Vendor`, `Creator`, `ClusterName`, `ClusterId`, `Name`). | `map(string)` | n/a | yes |
| metastore\_id | ID of the metastore the workspace is assigned to: the `metastore_id` of `databricks-metastore`. When system schemas are enabled, the plan fails if the workspace's current metastore is a different one. | `string` | n/a | yes |
| users\_group\_name | Account group that may use the policies (`CAN_USE`) and has cluster creation switched off: the `users_group_name` output of `databricks-workspace` (`<project>-workspace-users`). | `string` | n/a | yes |
| enable\_system\_schemas | Enable Unity Catalog system schemas (`system.<schema>` tables). Metastore-wide: set it in exactly one workspace, the governance workspace. | `bool` | `false` | no |
| max\_token\_lifetime\_days | Maximum lifetime of personal access tokens, in days (workspace setting `maxTokenLifetimeDays`). | `number` | `90` | no |
| restrict\_builtin\_users\_group | Also switch off unrestricted cluster creation for the workspace's built-in `users` group. Databricks grants that entitlement to it by default and every user belongs to it, so leaving it on defeats the policies. Set to false only if the workspace's built-in group is managed elsewhere. | `bool` | `true` | no |
| system\_schemas | System schemas to enable when `enable_system_schemas` is true. See the Databricks system tables documentation for the names. | `list(string)` | <pre>[<br/>  "access",<br/>  "billing",<br/>  "compute",<br/>  "lakeflow",<br/>  "query",<br/>  "storage"<br/>]</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| cluster\_policy\_ids | IDs of the installed cluster policies, keyed by policy name. |
<!-- END_TF_DOCS -->
