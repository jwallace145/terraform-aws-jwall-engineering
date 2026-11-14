# databricks-catalog

A workspace's own Unity Catalog catalog, on managed storage in a dedicated
bucket that is reachable **only through Unity Catalog**: the core of a
project's **workspace stack**. Creates:

- the catalog bucket `<p>-databricks-catalog` (Block Public Access, SSE-S3
  with a bucket key, `BucketOwnerEnforced`, versioning off, `force_destroy`)
  and its bucket policy (below);
- the Unity Catalog role `<p>-databricks-uc`, trusting Databricks' Unity
  Catalog master role with the storage credential's external ID and itself
  (self-assuming), with Databricks' Unity Catalog permissions scoped to the
  bucket;
- the storage credential and the external location
  `s3://<p>-databricks-catalog/managed/`, both isolated;
- the catalog `<project>` in snake_case (`databricks-poc` gives
  `databricks_poc`): isolated, `storage_root` = the external location, owned by
  `<project>-workspace-admins`, `tags` as its properties;
- workspace bindings of the catalog, the external location and the storage
  credential to `workspace_id`;
- grants: on the catalog, `ALL_PRIVILEGES` for the admin group and
  `USE_CATALOG`, `USE_SCHEMA`, `CREATE_SCHEMA`, `CREATE_TABLE`, `SELECT`,
  `MODIFY` for the users group (no `ALL_PRIVILEGES`, no `MANAGE`); on the
  external location, `ALL_PRIVILEGES` for the admin group only.

`<p>` is `<name_root>-<project>`, for example
`jwall-engineering-databricks-poc`. The bucket and role names are the ones
`databricks-workspace`'s `s3_endpoint_policy` admits, so `name_root` and
`project` must equal that module's.

## Workspace stack

The module needs a **workspace-level** `databricks` provider (`host` = the
account stack's `workspace_url` output) and the AWS provider; it configures
neither. It is applied after `databricks-workspace`, and takes that module's
`workspace_id`, `admin_group_name` and `users_group_name` outputs.

## Bucket policy

Data in the bucket is guarded against every principal that cannot rewrite the
bucket policy or the Unity Catalog role's trust (see "Known gaps"):

| Statement | Effect | Actions | Who |
| --- | --- | --- | --- |
| `DenyObjectAccessExceptUC` | Deny | `s3:GetObject*`, `s3:PutObject*` on objects | everyone whose `aws:PrincipalArn` is not the Unity Catalog role (`ArnNotEquals`) |
| `DenyDeleteExceptUCAndApply` | Deny | `s3:DeleteObject*` on objects | everyone except the Unity Catalog role and `apply_role_arn` |
| `AllowApplyEmpty` | Allow | `s3:ListBucket`, `s3:ListBucketVersions`, `s3:DeleteObject`, `s3:DeleteObjectVersion` | `apply_role_arn` |

The explicit denies override any IAM allow, so a principal's own IAM
permissions do not open the data. `management_role_arns` (CI plan, admin) get
no statement: they keep their IAM rights to the bucket's configuration but
cannot read, write or delete objects as themselves. A precondition rejects the Unity Catalog role in
`management_role_arns` or `apply_role_arn`.

Only object actions are denied, so the apply role (and Terraform) can still
manage the bucket's configuration and this policy.

**Why the apply role may only list and delete.** Destroy must be able to empty
the bucket (see "Destroy order") so a proof of concept can be torn down and
rebuilt, but the apply role should not be a routine path to the data. Listing
and deleting is all emptying needs; reading or putting objects would bypass
Unity Catalog.

**Why `tags` requires only `Project` and `Owner`.** The tags become catalog
properties (`databricks_catalog.properties`), which describe the catalog and
nothing else, so only the two that identify it are required. The workspace
modules (`databricks-workspace`, `databricks-workspace-config`) put their tags
on cluster resources, where cost attribution needs all six governance tags
(`Project`, `Environment`, `CostCenter`, `Workspace`, `Owner`, `ManagedBy`).

## Unity Catalog role and the external ID

Databricks requires storage credential roles to be self-assuming and to trust
its Unity Catalog master role with an external ID that it issues when the
credential is created
([Databricks: create a storage credential for S3](https://docs.databricks.com/aws/en/connect/unity-catalog/cloud-storage/s3/s3-external-location-manual)).
The module does it in one apply:

1. the storage credential is created with the role's ARN **built from its
   name** (it cannot reference the role, whose trust needs the credential);
2. the role's trust comes from `databricks_aws_unity_catalog_assume_role_policy`
   with the credential's external ID, and its permissions from
   `databricks_aws_unity_catalog_policy` for the bucket;
3. a 30 s `time_sleep` lets IAM propagate before the external location, which
   validates the credential, is created.

The trust policy is read after the credential exists, so a plan of a new stack
shows it as known after apply.

## Destroy order

1. The CLI empties the catalog bucket with the apply role **before**
   `terraform destroy`, while the bucket policy still stands: `AllowApplyEmpty`
   authorizes this (a same-account Allow in the resource policy suffices).
   The bucket is emptied directly, not through Unity Catalog's delayed cleanup
   of managed data.
2. `terraform destroy` of the workspace stack removes grants and bindings, the
   catalog (`force_destroy`, dropping its schemas and tables), the external
   location and storage credential (both `force_destroy`), the role, the
   bucket policy and the now empty bucket.
3. The account stack is destroyed.

The bucket's `force_destroy = true` is only a backstop. Terraform destroys the
bucket policy before the bucket, so the backstop runs without
`AllowApplyEmpty` and relies on the apply role's IAM identity policy (the
`databricks/manage` CI policy leaf grants list and delete on this bucket).
Callers who run plain `terraform destroy` without step 1 depend on that grant.

Removing a binding of the current workspace does not block deleting the
securable: the provider re-binds the current workspace before deleting an
isolated catalog, external location or storage credential.

## Validation

- `project`: kebab-case; `<p>-databricks-catalog` at most 63 characters.
- `apply_role_arn`, `management_role_arns`: IAM role ARNs.
- `workspace_id`: a positive integer.
- `tags`: must contain `Project` and `Owner`.

## Known gaps

- Data is guarded against every principal that cannot rewrite the bucket policy
  or the UC role's trust: the CI apply role and account admins can, and are
  trusted. The plan role cannot.
- The Unity Catalog role's trust and permissions come from the provider's
  helper data sources as JSON rather than `jsonencode()`, so they follow
  Databricks' documented shapes; the tests decode and check them. The bucket
  policy is built with `jsonencode()`.
- The permissions helper also grants Databricks' managed file events
  statements (`s3:GetBucketNotification`/`PutBucketNotification` on the bucket,
  SNS and SQS actions on `csms-*` topics and queues in any region of the
  account). No `Resource = "*"`.
- An isolated securable created by Terraform is already bound to the workspace
  it was created from; the explicit bindings make that state declarative.
- The catalog bucket is reachable from the workspace VPC only through its S3
  endpoint policy and only as the Unity Catalog role; serverless compute does
  not traverse that endpoint (see `databricks-workspace`).

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/databricks-catalog>

## Usage

```hcl
module "catalog" {
  source  = "jwallace145/jwall-engineering/aws//modules/databricks-catalog"
  version = "~> 0.18"

  project          = "databricks-poc"
  workspace_id     = var.workspace_id     # databricks-workspace's workspace_id
  admin_group_name = var.admin_group_name # databricks-workspace's admin_group_name
  users_group_name = var.users_group_name # databricks-workspace's users_group_name

  apply_role_arn       = "arn:aws:iam::111122223333:role/jwall-engineering-databricks-poc-ci-apply"
  management_role_arns = ["arn:aws:iam::111122223333:role/jwall-engineering-databricks-poc-ci-plan"]

  tags = module.context.tags
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
| [aws_iam_role.uc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.uc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [databricks_catalog.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/catalog) | resource |
| [databricks_external_location.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/external_location) | resource |
| [databricks_grants.catalog](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/grants) | resource |
| [databricks_grants.external_location](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/grants) | resource |
| [databricks_storage_credential.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/storage_credential) | resource |
| [databricks_workspace_binding.catalog](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/workspace_binding) | resource |
| [databricks_workspace_binding.external_location](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/workspace_binding) | resource |
| [databricks_workspace_binding.storage_credential](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/workspace_binding) | resource |
| [time_sleep.uc_role_propagation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [databricks_aws_unity_catalog_assume_role_policy.uc](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/aws_unity_catalog_assume_role_policy) | data source |
| [databricks_aws_unity_catalog_policy.uc](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/aws_unity_catalog_policy) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| admin\_group\_name | Account group that owns the catalog and gets `ALL_PRIVILEGES` on it and on the external location: the `admin_group_name` output of `databricks-workspace` (`<project>-workspace-admins`). | `string` | n/a | yes |
| apply\_role\_arn | ARN of the CI apply role. The bucket policy lets it list and delete objects (so `destroy` can empty the bucket) and denies it reading or writing them. | `string` | n/a | yes |
| project | Project in kebab-case, for example `databricks-poc`; must equal `databricks-workspace`'s. The catalog is the project in snake\_case (`databricks_poc`). | `string` | n/a | yes |
| tags | Properties of the catalog (`databricks_catalog.properties`), for example the governance tags. Must contain `Project` and `Owner`. | `map(string)` | n/a | yes |
| users\_group\_name | Account group that may use the catalog, create schemas and tables in it, and read and modify data, but not manage it: the `users_group_name` output of `databricks-workspace` (`<project>-workspace-users`). | `string` | n/a | yes |
| workspace\_id | Numeric ID of the workspace the catalog, external location and storage credential are bound to: the `workspace_id` output of `databricks-workspace`, the workspace this stack's `databricks` provider points at. | `number` | n/a | yes |
| component | Value of the `Component` tag on every AWS resource. | `string` | `"databricks-catalog"` | no |
| management\_role\_arns | ARNs of the other roles that manage the account (CI plan, admin). Used only to reject passing the Unity Catalog role (a precondition); it grants nothing and adds no statement to the bucket policy, whose denies already cover every principal but the Unity Catalog role (and, for delete, `apply_role_arn`). | `list(string)` | `[]` | no |
| name\_root | Prefix of AWS resource names, in kebab-case; must equal `databricks-workspace`'s. With `<p>` = `<name_root>-<project>`, the bucket is `<p>-databricks-catalog` and the Unity Catalog role `<p>-databricks-uc`, the names the workspace's S3 endpoint policy admits. | `string` | `"jwall-engineering"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| bucket\_name | Name of the catalog bucket (`<p>-databricks-catalog`); Unity Catalog managed storage is under `managed/`. |
| catalog\_name | Name of the workspace's catalog: the project in snake\_case, for example `databricks_poc`. |
| external\_location\_name | Name of the Unity Catalog external location at `s3://<bucket>/managed/`, the catalog's storage root. |
| storage\_credential\_name | Name of the Unity Catalog storage credential for the role. |
| uc\_role\_arn | ARN of the Unity Catalog role (`<p>-databricks-uc`), the only principal that may read or write the bucket's objects. |
<!-- END_TF_DOCS -->
