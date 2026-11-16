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
