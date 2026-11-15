# databricks-workspace

A Databricks workspace on AWS in a customer-managed VPC: the core of a
project's **account stack**. Creates:

- the workspace security group `<p>-databricks-workspace` (all traffic within
  the group; outbound TCP to `0.0.0.0/0` only on the ports Databricks
  documents for a customer-managed VPC: 443, 3306, 53, 6666, 2443, 5432 and
  8443-8451) and the `databricks_mws_networks` configuration for the given
  private subnets;
- the root bucket `<p>-databricks-root` (Block Public Access, SSE-S3 with a
  bucket key, `BucketOwnerEnforced`, `force_destroy`) with the policy
  Databricks documents, admitting only principals tagged with this Databricks
  account's ID, and its storage configuration;
- the cross-account role `<p>-databricks-cross-account`, trusting Databricks
  with `sts:ExternalId` equal to the account ID and carrying Databricks'
  **customer-managed VPC** policy, then (after 20 s for IAM propagation) the
  Databricks credentials;
- the workspace `<project>-<environment>` (PREMIUM, `us-east-1`, `tags` as its
  `custom_tags`, optional `deployment_name`), assigned to the region's
  metastore;
- the account groups `<project>-workspace-admins` (the admin users and the
  automation service principal; `ADMIN` on the workspace) and
  `<project>-workspace-users` (the users; `USER`).

`<p>` is `<name_root>-<project>`, for example
`jwall-engineering-databricks-poc`.

## Two stacks

The module needs an **account-level** `databricks` provider
(`host = "https://accounts.cloud.databricks.com"`, authentication and account
ID from the environment) and the AWS provider; it configures neither. The
account stack composes `vpc` (private subnets and the S3 gateway endpoint),
`nat-instance` and this module, and looks up `metastore_id`.

Workspace-level resources (catalogs, cluster policies, ...) need a provider
whose `host` is the workspace, which does not exist until this module has been
applied. They live in a separate **workspace stack**, applied afterwards: its
`databricks` provider takes `host = workspace_url`, and it uses
`admin_group_name` and `users_group_name` for grants. The automation service
principal is a workspace admin, so the same credentials work in both stacks.

## Validation

- `subnet_ids`: at least two. Each subnet is read and must be in `vpc_id` with
  a netmask between /17 and /26 (Databricks' limits); `vpc` does not enforce
  this, so subnets from any source are checked here. Subnets created in the
  same apply are checked during apply.
- `project`: at most 24 characters, and short enough that
  `<p>-databricks-cross-account` fits IAM's 64 characters (21 with the default
  `name_root`), which also keeps `<p>-databricks-catalog` within S3's 63.
- `<project>-<environment>` (the workspace name): at most 30 characters.
- `deployment_name`: `null` or `^[a-z0-9-]{3,30}$`.
- `tags`: must contain `Project`, `Environment`, `CostCenter`, `Workspace`,
  `Owner` and `ManagedBy`, and no key Databricks reserves (`Vendor`,
  `Creator`, `ClusterName`, `ClusterId`, `Name`).
- `read_only_datasets`: kebab-case keys (at most 40 characters), S3 bucket
  names, prefixes of one or more segments ending in `/` (no leading `/`, no
  `*`), an IAM role ARN, and never the workspace's own root or catalog bucket
  or its own Unity Catalog role.

## S3 endpoint policy

The `s3_endpoint_policy` output is the policy for the VPC's S3 gateway endpoint
(`vpc`'s `s3_gateway_endpoint.policy`). Compute in the workspace VPC can reach
the catalog bucket only as the Unity Catalog role (`<p>-databricks-uc`), so
pasted foreign credentials cannot read data outside Unity Catalog. It allows
`s3:*` on:

- the Databricks-owned us-east-1 buckets the classic compute plane needs
  (artifacts, logs, system tables, sample datasets; see `local.databricks_buckets`),
- the workspace root bucket (its own bucket policy is the real guard),
- the catalog bucket, only under `ArnEquals aws:PrincipalArn` = the Unity
  Catalog role;
- each of `read_only_datasets` (shared datasets), only `s3:GetObject` under
  its prefix and `s3:ListBucket`/`s3:GetBucketLocation` on its bucket, only for
  that dataset's own share role (`ReadOnlyDataset<Name>`, one statement per
  dataset, so a role reaches only its own dataset).

Everything else is denied at the endpoint. The endpoint grants nothing: a
dataset is readable only once its own bucket policy names the share role as a
reader (a `dataset-bucket`'s `reader_role_arns`), so the project that owns the
data decides. The share role and the dataset's one read-only external location
come from `databricks-shared-dataset`, whose `endpoint_dataset` output is the
value to pass here; every consumer workspace passes the same entry. The role is named in a condition,
never in `Principal`, because the endpoint is created before the role exists.
The policy depends on names, the account ID and the region only, so the
account stack can pass it to `vpc` without a dependency cycle.

Limits:

- Serverless compute does not traverse this endpoint; it is not covered
  (accepted gap).
- Only same-region S3 goes through the gateway endpoint. Cross-region S3 goes
  via the NAT and is not covered. The module is us-east-1 only.

## Known gaps

- `subnet_ids` is keyed by position (so IDs of subnets created in the same
  stack may be unknown at plan). Reordering the list re-keys the subnet checks;
  they are data sources, so nothing is replaced.
- The cross-account role's policy (`databricks_aws_crossaccount_policy`,
  `policy_type = "customer"`) grants its EC2 actions (`RunInstances`,
  `TerminateInstances`, `Describe*`, security group rule changes, launch
  templates, fleets, volumes) on `Resource = "*"`. This is Databricks' own
  customer-managed-VPC policy; the `restricted` type would scope it to the VPC
  and security group at the cost of tracking Databricks' policy changes here.
- The role's trust and both policies come from the provider's helper data
  sources as JSON rather than `jsonencode()`, so they follow Databricks'
  documented shapes; the tests decode and check them.
- The role trusts Databricks' AWS account root (`414351767826`) with the
  external ID, as Databricks requires for the cross-account role.
- Databricks validates the role when the credentials are created. If the
  first apply still fails on IAM propagation, apply again.
- The NAT (for example `nat-instance`) must route the private subnets before a
  cluster starts; the workspace itself does not need it to be created.
- New us-east-1 workspaces may be auto-assigned to the region's metastore by
  Databricks, in which case `databricks_metastore_assignment` could fail with
  "already assigned" on the first apply. To be confirmed on the first live
  apply.
- `deployment_name` is optional and not computed in provider 1.142, so leaving
  it null may show drift after the workspace is created. Pass it explicitly
  (recommended).

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/databricks-workspace>

## Usage

```hcl
module "workspace" {
  source  = "jwallace145/jwall-engineering/aws//modules/databricks-workspace"
  version = "~> 0.18"

  account_id   = "11111111-2222-3333-4444-555555555555"
  project      = "databricks-poc"
  environment  = "dev"
  vpc_id       = module.network.vpc_id
  subnet_ids   = module.network.private_subnet_ids
  metastore_id = data.databricks_metastore.this.metastore_id
  tags         = module.context.tags

  admin_user_names                 = ["owner@example.com"]
  user_names                       = ["analyst@example.com"]
  service_principal_application_id = "00000000-0000-0000-0000-000000000000"
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
| [aws_iam_role.cross_account](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.cross_account](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_s3_bucket.root](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_ownership_controls.root](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.root](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.root](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.root](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [databricks_group.admins](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/group) | resource |
| [databricks_group.users](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/group) | resource |
| [databricks_group_member.admins](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/group_member) | resource |
| [databricks_group_member.service_principal](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/group_member) | resource |
| [databricks_group_member.users](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/group_member) | resource |
| [databricks_metastore_assignment.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/metastore_assignment) | resource |
| [databricks_mws_credentials.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/mws_credentials) | resource |
| [databricks_mws_networks.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/mws_networks) | resource |
| [databricks_mws_permission_assignment.admins](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/mws_permission_assignment) | resource |
| [databricks_mws_permission_assignment.users](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/mws_permission_assignment) | resource |
| [databricks_mws_storage_configurations.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/mws_storage_configurations) | resource |
| [databricks_mws_workspaces.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/mws_workspaces) | resource |
| [time_sleep.iam_propagation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_subnet.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |
| [databricks_aws_assume_role_policy.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/aws_assume_role_policy) | data source |
| [databricks_aws_bucket_policy.root](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/aws_bucket_policy) | data source |
| [databricks_aws_crossaccount_policy.this](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/aws_crossaccount_policy) | data source |
| [databricks_service_principal.automation](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/service_principal) | data source |
| [databricks_user.admins](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/user) | data source |
| [databricks_user.users](https://registry.terraform.io/providers/databricks/databricks/latest/docs/data-sources/user) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| account\_id | Databricks account ID (a UUID). Also the external ID the cross-account role requires from Databricks. | `string` | n/a | yes |
| admin\_user\_names | Databricks user names (email addresses) of the workspace admins, for example `["owner@example.com"]`. Each user must already exist in the account; they join `<project>-workspace-admins`. | `list(string)` | n/a | yes |
| environment | Environment in kebab-case, for example `dev`. The workspace is named `<project>-<environment>`, at most 30 characters. | `string` | n/a | yes |
| metastore\_id | ID of the region's Unity Catalog metastore that the workspace is assigned to, the `metastore_id` output of `databricks-metastore` (the stack looks it up). | `string` | n/a | yes |
| project | Project in kebab-case, for example `databricks-poc`. Names the workspace (`<project>-<environment>`), its groups (`<project>-workspace-admins`, `<project>-workspace-users`) and, through `<p>`, its AWS resources. At most 21 characters with the default name\_root, so `<p>-databricks-cross-account` fits IAM's 64 and `<p>-databricks-catalog` S3's 63. | `string` | n/a | yes |
| service\_principal\_application\_id | Application (client) ID of the account-level service principal that automation authenticates as. It joins the admin group, so the workspace stack can manage the workspace. | `string` | n/a | yes |
| subnet\_ids | IDs of the private subnets of vpc\_id for the workspace's clusters, for example the `private_subnet_ids` output of `vpc`: at least two, each in a different availability zone, each with a netmask between /17 and /26 (checked against the subnet when it is read). | `list(string)` | n/a | yes |
| tags | Tags Databricks puts on the workspace's cluster resources (`custom_tags`), as AWS does not apply the caller's default\_tags to them. Must contain `Project`, `Environment`, `CostCenter`, `Workspace`, `Owner` and `ManagedBy`, and no key Databricks reserves (`Vendor`, `Creator`, `ClusterName`, `ClusterId`, `Name`). | `map(string)` | n/a | yes |
| vpc\_id | ID of the VPC the workspace's clusters run in, for example the `vpc_id` output of `vpc`. It needs a NAT (for example `nat-instance`) for the private subnets' internet egress. | `string` | n/a | yes |
| component | Value of the `Component` tag on every AWS resource. | `string` | `"databricks-workspace"` | no |
| deployment\_name | Deployment name, the first label of the workspace URL (`<deployment_name>.cloud.databricks.com`). `null` (the default) lets Databricks pick one. Only possible if the account allows custom deployment names. | `string` | `null` | no |
| name\_root | Prefix of AWS resource names, in kebab-case. With `<p>` = `<name_root>-<project>`, the root bucket is `<p>-databricks-root`, the cross-account role `<p>-databricks-cross-account` and the security group `<p>-databricks-workspace`. | `string` | `"jwall-engineering"` | no |
| read\_only\_datasets | Shared datasets the workspace may read through Unity Catalog, keyed by the dataset's kebab-case name, for example `{ rusty-chess-nnue = { bucket = "jwall-engineering-rusty-chess-nnue", prefix = "data/", role_arn = "arn:aws:iam::111122223333:role/jwall-engineering-rusty-chess-nnue-databricks-share" } }`: the `endpoint_dataset` output of `databricks-shared-dataset`. Each adds one statement to the S3 endpoint policy allowing `s3:GetObject` under the prefix and `s3:ListBucket`/`s3:GetBucketLocation` on the bucket, only for that dataset's role. The endpoint grants nothing: the dataset's bucket policy must name the role as a reader. | <pre>map(object({<br/>    bucket   = string<br/>    prefix   = string<br/>    role_arn = string<br/>  }))</pre> | `{}` | no |
| user\_names | Databricks user names (email addresses) of the workspace's non-admin users. Each user must already exist in the account; they join `<project>-workspace-users`. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| admin\_group\_name | Account group with ADMIN on the workspace (`<project>-workspace-admins`). |
| cross\_account\_role\_arn | ARN of the cross-account role Databricks assumes to run clusters in the VPC. |
| root\_bucket\_name | Name of the workspace root bucket (`<p>-databricks-root`). |
| s3\_endpoint\_policy | Policy for the VPC's S3 gateway endpoint (`vpc`'s `s3_gateway_endpoint.policy`): the Databricks-owned buckets, the root bucket, the catalog bucket only for the Unity Catalog role, and read actions on each of `read_only_datasets` (under its prefix) only for that dataset's role. Built from names only, so it is known before the workspace exists. |
| security\_group\_id | ID of the workspace clusters' security group. |
| users\_group\_name | Account group with USER on the workspace (`<project>-workspace-users`). |
| workspace\_id | Numeric ID of the workspace. |
| workspace\_url | URL of the workspace, for example `https://dbc-01234567-89ab.cloud.databricks.com`: the `host` of the workspace stack's `databricks` provider. |
<!-- END_TF_DOCS -->
