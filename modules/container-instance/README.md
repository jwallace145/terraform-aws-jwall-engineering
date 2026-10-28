# container-instance

One EC2 instance that runs one image tag from ECR as a long-lived container
named `app`, with rollouts that never interrupt the work in progress. Built
for a Lichess bot (a game must finish before the engine is swapped), but
nothing in it is specific to chess: the image, the secrets, the environment,
the health check and the stop signal are inputs.

What it creates: the instance (latest Amazon Linux 2023 by public SSM
parameter, IMDSv2 only, an encrypted gp3 root volume, a public IPv4 address,
standard CPU credits), a security group with **no ingress rules**, an
instance role, a CloudWatch log group `/<name_root>/<project>/bot` and the
user data that installs Docker, the reconciler and the records sync.
Operators get a shell through Session Manager; there is no SSH key.

Every resource, including the root volume, carries `Name` and `Component`;
the organisation tags come from the caller's provider `default_tags`.

## How a rollout works

The instance and the release tooling share four SSM parameters under
`/<name_root>/<project>/bot/`:

| Parameter | Written by | Meaning |
|---|---|---|
| `desired-version` | the deploy (release role) | The image tag that should run |
| `running-version` | the reconciler | The tag that is running and healthy |
| `status` | the reconciler | `ok`, `waiting:<tag>`, `rolling-back:<reason>` or `failed:<reason>` |
| `last-sync` | the records sync | Time of the last successful upload of game records |

A deploy writes `desired-version` and runs `container-reconcile-async`
through Run Command, which starts the reconciler as its own systemd unit,
so a command timeout can never cut a swap in half. Then it follows the
parameters. The reconciler, `/usr/local/bin/container-reconcile`:

1. takes a lock, so only one reconcile runs at a time; a second one waits
   for the first and then converges to the newest desired tag;
2. does nothing if the desired tag is already running (`--restart` forces a
   swap anyway, for example after rotating a secret);
3. pulls the new tag and reads the secrets. Both happen before the running
   container is touched: if either fails, the old version keeps playing and
   the status says why;
4. ships finished records, clears the old container's restart policy and
   sends it **one** stop signal (`SIGINT`); then **waits as long as it
   takes** for it to exit on its own, writing `waiting:<tag>` every minute.
   It never kills the container: lichess-bot finishes the game in progress
   first, so a game is never resigned or aborted by a rollout;
5. ships the records again; if a newer tag was deployed while it waited,
   switches to that one; then starts the new tag and gives it
   `health_seconds` to stay up and log `health_log_pattern`;
6. on success writes `running-version` and `ok`; if the new tag does not
   start or does not become healthy, removes it, writes
   `rolling-back:<reason>`, starts the previous tag again and ends with
   `failed:<reason>`.

Every run ends with `ok` or `failed:<reason>`, including on an unexpected
error, so the release tooling never waits on a run that has died. A failed
progress write (`waiting:<tag>`) never interrupts a swap.

The same reconciler runs once at boot, so a rebooted or replaced instance
converges to `desired-version` on its own.

Trigger it by hand:

```sh
aws ssm send-command --document-name AWS-RunShellScript \
  --targets Key=tag:Project,Values=<project> Key=tag:Component,Values=container-instance \
  --parameters 'commands=["container-reconcile-async"]'
```

**What replaces the instance.** Changing the AMI (a new Amazon Linux
release, picked up at the next apply), the instance type or anything in the
user data (any input of this module except tags) replaces the instance and
ends the container's current work. Plan before applying and apply while the
bot is idle. At a clean shutdown (an instance replacement, a stop or a
reboot) the records are shipped one last time after the container has
exited, including games that ended seconds before.

## Game records

When `records_bucket_name` is set, the container's `records_container_path`
is mounted from `/var/lib/container-instance/records/<tag>/`, one directory
per image tag, so every game is attributed to the engine version that played
it, even when a swap and a sync overlap. Every 10 minutes, around every
swap and at shutdown, `/usr/local/bin/container-records-sync` ships each
**finished** game (a `1-0`, `0-1` or `1/2-1/2` result, untouched for a
minute) to:

```
s3://<bucket>/<records_prefix>pgn/schema=1/engine=<tag>/date=<YYYY-MM-DD>/<game_id>.pgn
s3://<bucket>/<records_prefix>meta/schema=1/engine=<tag>/date=<YYYY-MM-DD>/<game_id>.json
```

The `.pgn` object is the file the bot wrote, byte for byte (with the
engine's evaluation comments). The `.json` sidecar is one object per game
with exactly these keys:

| Key | Type | Value |
|---|---|---|
| `schema` | int | `1` |
| `game_id` | string | The Lichess game id (8 characters) |
| `engine_version` | string | The image tag that played the game |
| `image` | string | `<repository url>:<tag>` |
| `bot` | string | `bot_name` |
| `instance_id` | string | The EC2 instance |
| `white`, `black`, `result` | string | From the PGN headers |
| `utc_date` | string | `YYYY-MM-DD` |
| `utc_time`, `time_control`, `variant`, `event`, `site` | string or null | From the PGN headers |
| `white_elo`, `black_elo` | int or null | From the PGN headers |
| `termination` | string or null | From the PGN headers |
| `headers` | object | Every PGN header as written |
| `source_file` | string | The file name on the instance |
| `sha256` | string | SHA-256 of the `.pgn` object |
| `synced_at` | string | ISO 8601 UTC time of staging |

The `key=value` path segments are Hive-style partitions, so Athena, Spark
or DuckDB can read `meta/` as a table partitioned by schema, engine and
date. The sync only adds objects: it keeps a local record of what it
shipped and never uploads a game twice, never runs with `--delete`, and the
instance role cannot read or delete records. If an object were ever
overwritten, bucket versioning keeps the old version (30 days by default in
`private-bucket`). Unfinished games and files it cannot place (no game id or
no date) are skipped and counted in the journal. Games that finished in the
last few minutes before an instance is lost without a clean shutdown are
not shipped. A game in progress when an instance is replaced is lost; if
lichess-bot resumes it in a new container, the finished game is filed
under the new container's tag, which played its last moves. Any change to the layout or
the sidecar keys is a new `schema=` value, never an edit of `schema=1`.

## Access

```sh
aws ssm start-session --target <instance_id>
sudo journalctl -u 'container-reconcile*' -u container-records-sync
sudo docker logs app
cat /etc/container-instance/config.env   # no secret values: those are read at container start
```

Secret values reach the container through an env file that is deleted
right after `docker run`; Docker keeps them in the container's
configuration on the instance's encrypted root volume.

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/container-instance>

## Usage

```hcl
module "bot" {
  source  = "jwallace145/jwall-engineering/aws//modules/container-instance"
  version = "~> 0.10"

  name                 = "jwall-engineering-rusty-chess-bot"
  project              = "rusty-chess"
  image_repository_url = module.image.url
  image_repository_arn = module.image.arn
  vpc_id               = module.network.vpc_id
  subnet_id            = module.network.public_subnet_ids[0]

  secret_parameters      = { LICHESS_TOKEN = "/jwall-engineering/rusty-chess/lichess-token" }
  container_environment  = { ENGINE_HASH_MB = "128" }
  bot_name               = "rusty-chess-bot"
  records_bucket_name    = module.records.name
  records_container_path = "/opt/lichess-bot/game_records"
  health_log_pattern     = "awaiting challenges"
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11 |
| aws | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_instance_profile.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.all_ipv4](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_ssm_parameter.ami](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| image\_repository\_arn | ARN of the same ECR repository (output `arn` of `ecr-repository`), which the instance may pull from. | `string` | n/a | yes |
| image\_repository\_url | URL of the ECR repository the image tags come from (output `url` of `ecr-repository`). | `string` | n/a | yes |
| name | Name of the instance, its role, instance profile and security group, in kebab-case, for example `jwall-engineering-rusty-chess-bot`. Start it with `<name_root>-<project>-` so the `container/*` CI policies can manage it. | `string` | n/a | yes |
| project | Project in kebab-case, for example `rusty-chess`. Parameters live under `/<name_root>/<project>/bot/` and logs in `/<name_root>/<project>/bot`. | `string` | n/a | yes |
| subnet\_id | Public subnet of the instance (an element of `public_subnet_ids` of `vpc`). The instance gets a public IPv4 address for egress. | `string` | n/a | yes |
| vpc\_id | VPC of the security group (output `vpc_id` of `vpc`). | `string` | n/a | yes |
| architecture | CPU architecture of the AMI: `x86_64` or `arm64`. The image must be built for the same one. | `string` | `"x86_64"` | no |
| bot\_name | Name of the account the container plays as (for example the Lichess bot user), recorded in every game record's sidecar. | `string` | `""` | no |
| component | Value of the `Component` tag on every resource. The release CLI finds the instance by `Project` and this tag. | `string` | `"container-instance"` | no |
| container\_environment | Plain environment variables for the container. Values must not contain spaces. | `map(string)` | `{}` | no |
| health\_log\_pattern | Text the new container must log within `health_seconds` to count as healthy, for example `awaiting challenges`. Empty: it only has to stay up. | `string` | `""` | no |
| health\_seconds | How long a new container has to prove it is healthy before it is rolled back. | `number` | `90` | no |
| instance\_type | EC2 instance type. Must match `architecture` (t3 for x86\_64, t4g for arm64). | `string` | `"t3.micro"` | no |
| log\_retention\_days | Retention of the container's CloudWatch log group, in days. | `number` | `30` | no |
| name\_root | Prefix of parameter and log group paths, in kebab-case. | `string` | `"jwall-engineering"` | no |
| records\_bucket\_name | Bucket that finished game records are shipped to (output `name` of `private-bucket`). `null` disables the records sync. | `string` | `null` | no |
| records\_container\_path | Absolute path inside the container where it writes one `.pgn` file per game. Required when `records_bucket_name` is set; the host directory mounted there is per image tag. | `string` | `null` | no |
| records\_prefix | Key prefix in the records bucket. Below it the layout is fixed: `pgn/schema=1/engine=<tag>/date=<YYYY-MM-DD>/<game_id>.pgn` and the matching `meta/.../<game_id>.json` sidecar. | `string` | `"records/"` | no |
| root\_volume\_gb | Size of the gp3 root volume in GB. It holds Docker images and the game records until they are shipped. | `number` | `16` | no |
| secret\_parameters | Environment variables the container gets from SecureString parameters: variable name to parameter name, for example `{ LICHESS_TOKEN = "/jwall-engineering/rusty-chess/lichess-token" }`. The parameters are created out of band, never by Terraform; the instance may read exactly these. | `map(string)` | `{}` | no |
| stop\_poll\_seconds | How often the reconciler checks whether the stopping container has exited. | `number` | `15` | no |
| stop\_signal | Signal sent once to the running container to ask it to finish and exit. It is never followed by a kill. | `string` | `"SIGINT"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| instance\_arn | ARN of the instance. |
| instance\_id | ID of the instance, for Session Manager (`aws ssm start-session --target`) and Run Command. |
| log\_group\_arn | ARN of the log group. |
| log\_group\_name | CloudWatch log group the container logs to. |
| parameter\_names | The parameters the release tooling and the reconciler share: `desired_version` (written by a deploy), `running_version` and `status` (written by the reconciler), `last_sync` (written by the records sync). |
| parameter\_prefix | SSM path of the bot's parameters: `/<name_root>/<project>/bot`. |
| public\_ip | Public IPv4 address of the instance (egress only; nothing listens). |
| reconciler\_script | Internal: the installed reconciler script text, for tests. |
| records\_sync\_script | Internal: the installed records sync script text, for tests. |
| records\_uri | S3 URI the game records are shipped under, or null without a records bucket. |
| role\_arn | ARN of the instance role. |
| role\_name | Name of the instance role. |
| security\_group\_id | ID of the egress-only security group. |
<!-- END_TF_DOCS -->
