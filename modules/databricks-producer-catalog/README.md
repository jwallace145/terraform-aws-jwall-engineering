# databricks-producer-catalog

One Unity Catalog catalog per dataset producer, owned by the platform. Every
dataset the producer onboards becomes a schema in it, holding an external
volume `files` (`databricks-dataset`), so a consumer that is granted the
dataset finds it in Catalog Explorer at
`/Volumes/<catalog>/<dataset>/files/`. Applied through the shared-objects host
(`databricks-host-workspace`).

Creates:

- a catalog named after `producer` (`braveheart-selfplay` gives
  `braveheart_selfplay`), `ISOLATED`, owned by `owner_group_name`, with its
  managed location at `<storage_url>/<catalog>` (`databricks-catalog-storage`)
  and the property `producer`;
- a read-write binding to the host only.

Consumers are bound read-only, and granted `USE CATALOG`, by
`databricks-producer-catalog-access`, which owns the catalog's grants. The
owner is the platform, never the producer: a catalog's owner can grant anyone
access, which would bypass the producer/consumer handshake.

## Usage

See [examples/basic](examples/basic/main.tf).
