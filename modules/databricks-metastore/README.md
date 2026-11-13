# databricks-metastore

The Unity Catalog metastore for the Databricks account, and the admin group
that owns it. There is **one metastore per region per account**, and every
workspace in that region is assigned to it, so this module is instantiated
once, in the foundation stack, never per project.

The metastore has **no `storage_root`**: each project's catalog gets its own
managed location (its own bucket), so nothing is written to a metastore-level
bucket and no credential has to be shared across projects.

The owner is the admin group (`admin_group_name`), not a person. The group
holds the users in `admin_user_names` (looked up by user name, which is their
email address; they must already exist in the account) and the automation
service principal (looked up by `service_principal_application_id`), so the
foundation stack keeps control after a person leaves.

The module uses an **account-level** `databricks` provider
(`host = "https://accounts.cloud.databricks.com"`, authentication from the
environment) and never configures it.

**Adopting or deleting an existing metastore.** A Databricks account may
already have an auto-created metastore in `us-east-1`; creating a second one
fails. Whether to import it into this module or delete it first is the
caller's runbook, not decided here. Deleting a metastore detaches every
workspace from it.

No `Resource = "*"` policies are created here.

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/databricks-metastore>

## Usage

```hcl
provider "databricks" {
  host = "https://accounts.cloud.databricks.com"
}

module "metastore" {
  source  = "jwallace145/jwall-engineering/aws//modules/databricks-metastore"
  version = "~> 0.18"

  admin_user_names                 = ["owner@example.com"]
  service_principal_application_id = "00000000-0000-0000-0000-000000000000"
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
| [databricks_group.admins](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/group) | resource |
| [databricks_group_member.service_principal](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/group_member) | resource |
| [databricks_group_member.users](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/group_member) | resource |
| [databricks_metastore.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/metastore) | resource |
| [databricks_service_principal.automation](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/service_principal) | data source |
| [databricks_user.admins](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/user) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| admin\_user\_names | Databricks user names (email addresses) of the people who administer the metastore, for example `["owner@example.com"]`. Each user must already exist in the account. | `list(string)` | n/a | yes |
| service\_principal\_application\_id | Application (client) ID of the account-level service principal that automation authenticates as. It joins the admin group so the foundation stack keeps control of the metastore. | `string` | n/a | yes |
| admin\_group\_name | Account-level group that owns the metastore. | `string` | `"jwall-engineering-metastore-admins"` | no |
| name | Name of the metastore. There is one metastore per region per Databricks account, shared by every workspace in that region. | `string` | `"jwall-engineering-us-east-1"` | no |
| region | Region of the metastore. Only `us-east-1` is supported: every workspace of the account lives there. | `string` | `"us-east-1"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| admin\_group\_name | Name of the group that owns the metastore. |
| metastore\_id | ID of the metastore, for `databricks_metastore_assignment` in each workspace stack. |
<!-- END_TF_DOCS -->
