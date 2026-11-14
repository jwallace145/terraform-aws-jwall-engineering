# databricks/manage

Create, change and destroy what a Databricks workspace project's stacks build
beyond [`compute/manage`](../../compute/manage), with `<p>` =
`<name_root>-<project>`:

- the S3 gateway endpoint of [`vpc`](../../../vpc);
- the NAT instance of [`nat-instance`](../../../nat-instance), which owns its
  primary network interface and public IP (no separate interface or Elastic
  IP), its root volume's tags, and replacing the target of the routes to it;
- the root bucket `<p>-databricks-root` of
  [`databricks-workspace`](../../../databricks-workspace) and the catalog
  bucket `<p>-databricks-catalog` of
  [`databricks-catalog`](../../../databricks-catalog): their configuration,
  and emptying them for `force_destroy`;
- the Databricks credential in one SSM parameter and the project's event log,
  as in [`databricks/read`](../read).

Class: **write**. Pair it with `databricks/read`, `compute/read` and
`compute/manage` on the apply role. Databricks API calls need no AWS
permission.

Part of the [`ci-policies`](../..) catalog. Request it from a CI role module
with `policies = ["databricks/manage"]` and
`policy_inputs = { databricks = { secret_parameter_arn, events_object_arn } }`;
it is not meant to be called directly.

## What `compute/*` already grants

- The VPC, private subnets, private route table, their associations,
  `CreateRoute`/`DeleteRoute` on the route tables, and the security groups
  (the NAT's and the workspace's: create, tag on create, authorize ingress and
  egress, revoke the default egress, delete), by the `Project` tag.
- The roles `<p>-databricks-cross-account` and `<p>-databricks-uc` and their
  inline policies: its role scoping `<name_root>-<project>-*` covers them.
- Every refresh read of EC2 (`ec2:Describe*` in `compute/read`).

Tests in `ci-policies` check all three. This policy therefore grants no IAM
action. Neither role is passed to an AWS service (Databricks assumes them;
`databricks_mws_credentials` and `databricks_storage_credential` take the ARN
through the Databricks API), and the NAT has no instance profile, so there is
no `iam:PassRole`.

## How it is scoped

- **The endpoint.** `CreateVpcEndpoint` requires `aws:RequestTag/Project =
  <project>` and `ec2:VpceServiceName = com.amazonaws.us-east-1.s3`; the VPC,
  route tables and endpoint it touches afterwards need
  `aws:ResourceTag/Project = <project>`.
- **Routes.** `CreateRoute`, `ReplaceRoute` and `DeleteRoute` authorize only
  the route table, not the target, so routes to the NAT's untagged primary
  interface need no interface grant. `ReplaceRoute` (the interface changes
  when the instance is replaced) is here; the rest is in `compute/manage`.
- **The NAT instance.** `RunInstances` creates an instance only with
  `aws:RequestTag/Project = <project>` and `aws:RequestTag/Component =
  nat-instance` (`StringEquals`) and an `ec2:InstanceType` like `t4g.*`
  (`StringLike`), from an Amazon-owned image, in a project subnet and
  security group (`aws:ResourceTag/Project`). Its root volume must be
  launched with `Project = <project>` (the provider default tags). Its
  primary network interface is created untagged, so that resource is not
  tag-conditioned; the statements above bound the launch.
  `ModifyInstanceAttribute` (the provider sets `source_dest_check = false`
  right after launch) and `TerminateInstances` (which also deletes the
  primary interface and the volume) require the `Project` and `Component =
  nat-instance` tags on the instance.
- **Tags.** `CreateTags` with `ec2:CreateAction` in `CreateVpcEndpoint` and
  `RunInstances`, on endpoints, instances and volumes. The provider also tags
  the root volume with a separate `CreateTags` after launch (no
  `ec2:CreateAction`): allowed on volumes only when the request sets
  `Project = <project>` and `Component = nat-instance`, with tag keys limited
  to the organisation tags, `CostCenter`, `Workspace`, `Component` and `Name`
  (`ForAllValues:StringEquals` on `aws:TagKeys`).
- **Buckets by name.** Configuration of the two buckets. Of their objects,
  only `s3:ListBucket`, `s3:ListBucketVersions`, `s3:DeleteObject` and
  `s3:DeleteObjectVersion`: what `force_destroy` needs to empty them. Never
  `s3:GetObject` or `s3:PutObject`. The catalog bucket's `force_destroy`
  runs after its bucket policy is destroyed, so this grant is what lets a
  plain `terraform destroy` empty it.
- **Credential and event log** as in [`databricks/read`](../read).

## Known gaps

No statement uses `Resource = "*"`. Two statements are broader than one
project's resources:

| Statement | Why |
|---|---|
| `RunNatInterface` (`ec2:RunInstances` on `network-interface/*`, no condition) | The provider does not tag the primary interface RunInstances creates, so it cannot be scoped by tag. A launch still needs every other statement: a `t4g` instance tagged `Project` and `Component = nat-instance`, an Amazon image, a project subnet and security group. |
| `TagNatRootVolume` (`ec2:CreateTags` on `volume/*`) | The post-launch tag call has no `ec2:CreateAction`. It can stamp this project's NAT tags (only the known keys) on any volume in the account, which would bring that volume under the project's tag scope; no policy here can delete or attach a volume. |

## Known limitations

- Changing the NAT's `instance_type` or metadata options in place is denied:
  this policy grants no `StopInstances`, `StartInstances` or
  `ModifyInstanceMetadataOptions`, and a type change needs a stopped
  instance, so it cannot leave `t4g.*` through `ModifyInstanceAttribute`.
  Replacing the NAT's security group in place (which the provider applies to
  the untagged primary interface with `ModifyNetworkInterfaceAttribute`) is
  also denied. Replace the instance instead (`terraform apply -replace`);
  the routes are replaced to the new interface.
- `nat-instance` accepts the `t4g`, `c7g`, `c8g` and `m7g` families; this
  policy launches `t4g` only.
- The tag-scoped endpoint and route actions reach any VPC, route table or
  endpoint tagged with the project, not only the Databricks ones.

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
| [aws_iam_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| events\_object\_arn | Object ARN pattern of the project's event log, `arn:aws:s3:::jwall-engineering-databricks-audit-logs/events/project=<project>/*`. The policy may only put objects there: no read, no delete. | `string` | n/a | yes |
| name | Name of the managed policy, for example `jwall-engineering-databricks-poc-ci-apply-databricks-manage`. | `string` | n/a | yes |
| project | Project name in kebab-case, for example `databricks-poc`. Bucket names are built from `<name_root>-<project>` and EC2 is scoped by the `Project` tag. | `string` | n/a | yes |
| secret\_parameter\_arn | ARN of the one SSM SecureString parameter holding the Databricks credential, for example `arn:aws:ssm:us-east-1:123456789012:parameter/jwall-engineering/databricks-poc/databricks`. The policy may read and decrypt this parameter only. | `string` | n/a | yes |
| name\_root | Prefix of resource names, in kebab-case. With `<p>` = `<name_root>-<project>`, the buckets are `<p>-databricks-root` and `<p>-databricks-catalog`. | `string` | `"jwall-engineering"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the managed policy. |
| name | Name of the managed policy. |
| policy | The policy document as a JSON string. |
<!-- END_TF_DOCS -->