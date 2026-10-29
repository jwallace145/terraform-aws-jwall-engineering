# task-runner

Prepares a project's ephemeral CI task instances: a launch template, an
instance role and profile, an egress-only security group and a CloudWatch
log group. It launches nothing. The `jwall-engineering-sites` CLI
(`task run`) launches one on-demand instance per task from the template,
runs the task through SSM Run Command, streams its output, copies its
results and terminates the instance.

Names derive from `name_root` and `project`, and the
[`task/launch`](../ci-policies) CI policy depends on them:

| What | Name |
|---|---|
| Launch template, instance role, profile, security group | `<name_root>-<project>-task` |
| Log group | `/<name_root>/<project>/tasks` |
| Results | `s3://<name_root>-<project>-tasks/tasks/<run>/<task>/` |

The caller creates the results bucket, for example with
[`private-bucket`](../private-bucket) and `current_object_expiration_days`.

## Instances

- **Image:** a pinned `ami_id`, or the latest Amazon Linux 2023 image for
  `architecture` from its public SSM parameter. The launch role may launch
  Amazon-owned images only.
- **Type:** `default_instance_type`, `c8a.xlarge` by default. The CLI passes
  the type per launch; the launch role's allow-list
  ([`ci-task-role`](../ci-task-role)) decides which types may be launched.
- **Network:** the template sets the security group but no subnet. The CLI
  passes a public subnet per launch and tries the next availability zone
  when one has no on-demand capacity. There is no ingress and no SSH.
- **Setup:** the user data schedules the lifetime guard first, then installs
  `git`, `gcc`, `gcc-c++`, `make` and `tar`, and rustup with `rust_toolchain`
  (minimal profile) for root and `ec2-user`. It ends by writing
  `/etc/task-runner/ready` with the image, toolchain, CPU model and physical
  core count, which tasks wait for. The steps are in
  [`files/task-setup.sh`](files/task-setup.sh).
- **Disk:** an encrypted gp3 root volume of `root_volume_gb`, deleted with
  the instance.

## Leak guards

An instance that outlives its task costs money until something ends it.
Four things do:

1. the CLI terminates the instance on every exit path, including SIGINT and
   SIGTERM when GitHub cancels the job;
2. the consumer workflow's `always()` step terminates anything tagged with
   its run;
3. the instance shuts itself down `max_lifetime_hours` after boot, and a
   shutdown terminates it (`instance_initiated_shutdown_behavior`);
4. `task sweep` in the CLI terminates leftovers by hand.

## Permissions

Tasks run pull request code, so the instance role can only write. It can
write to the task log group and put objects under the results prefix, and
it has the SSM agent's registration and message channels for Run Command
and Session Manager. It cannot read earlier results, pull images, or read
parameters or secrets. `AmazonSSMManagedInstanceCore` is deliberately not
attached: it grants `ssm:GetParameter` on every parameter in the account,
which would expose secrets such as a bot's token to a pull request.

The launch template and the instance's own guards bound accidents, not
abuse: task code runs as root and could cancel the scheduled shutdown. The
CLI's termination and the workflow's `always()` step remain the primary
cleanup.

## Launch contract

`task/launch` requires `Project` and `Purpose = ci-task` as request tags on
both the instance and its volume. The template tags both, and the CLI must
also send `instance` and `volume` tag specifications carrying them.

## Cost and tags

Instances are on-demand only, never spot, so a task is never interrupted.
A `c8a.xlarge` costs about $0.2 an hour in us-east-1. When no task runs,
the cost is zero apart from stored logs and results. The template tags
every instance and volume `Component = task-runner` and `Purpose = ci-task`.
The CLI adds the organisation tags at launch, so cost reports can group
task spend by `Project`, `Component` or `Purpose`.

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/task-runner>

## Usage

```hcl
module "task_results" {
  source  = "jwallace145/jwall-engineering/aws//modules/private-bucket"
  version = "~> 0.12"

  name                           = "jwall-engineering-rusty-chess-tasks"
  current_object_expiration_days = 7
}

module "tasks" {
  source  = "jwallace145/jwall-engineering/aws//modules/task-runner"
  version = "~> 0.12"

  project        = "rusty-chess"
  vpc_id         = module.vpc.vpc_id
  rust_toolchain = "1.91.0"
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
| [aws_launch_template.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.all_ipv4](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_ssm_parameter.ami](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| project | Project in kebab-case, for example `rusty-chess`. Names derive from it: `<name_root>-<project>-task`, the log group `/<name_root>/<project>/tasks` and the results bucket `<name_root>-<project>-tasks`, which the caller creates. | `string` | n/a | yes |
| vpc\_id | VPC of the task security group. Instances launch into the project's public subnets of this VPC, which the CLI picks per launch. | `string` | n/a | yes |
| ami\_id | Image of the task instances, an Amazon-owned Amazon Linux 2023 image (the launch role may launch no other). `null` follows the latest one through `/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-<architecture>`; pin it for reproducible task environments. | `string` | `null` | no |
| architecture | CPU architecture of the image: `x86_64` or `arm64`. The instance types launched must match it. | `string` | `"x86_64"` | no |
| default\_instance\_type | Instance type of the template. The CLI passes the type per launch; which types may be launched is the launch role's allow-list (`ci-task-role`), not this module's. | `string` | `"c8a.xlarge"` | no |
| log\_retention\_days | Days CloudWatch keeps task output. | `number` | `14` | no |
| max\_lifetime\_hours | Hours after boot at which an instance shuts itself down, and so terminates, whatever it is doing. It bounds the cost of an instance the CLI failed to terminate. | `number` | `6` | no |
| name\_root | Prefix of every name, in kebab-case. The template, role, profile and security group are `<name_root>-<project>-task`. | `string` | `"jwall-engineering"` | no |
| root\_volume\_gb | Size of the encrypted gp3 root volume in GB, deleted with the instance. It holds the toolchain, the checkout and the build. | `number` | `40` | no |
| rust\_toolchain | Rust toolchain the setup installs with rustup: `stable`, a channel like `nightly-2026-10-01`, or a version like `1.91.0`. Pin a version for reproducible builds. | `string` | `"stable"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| instance\_profile\_arn | ARN of the task instance profile. |
| instance\_role\_name | Name of the task instance role, the only role the launch role may pass. |
| launch\_template\_id | ID of the task launch template. |
| launch\_template\_name | Name of the task launch template, `<name_root>-<project>-task`. The CLI launches its `$Default` version. |
| log\_group\_name | CloudWatch log group that Run Command streams task output to. |
| results\_uri | S3 prefix under which each task's outputs land, as `<results_uri><run>/<task>/`. The bucket is the caller's. |
| security\_group\_id | ID of the task security group: egress only. |
<!-- END_TF_DOCS -->
