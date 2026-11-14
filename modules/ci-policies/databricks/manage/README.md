# databricks/manage

Create, change and destroy what a Databricks workspace project's stacks build
beyond [`compute/manage`](../../compute/manage), with `<p>` =
`<name_root>-<project>`:

- the S3 gateway endpoint of [`vpc`](../../../vpc);
- the NAT of [`nat-instance`](../../../nat-instance): its network interface,
  Elastic IP (allocate, associate, disassociate, release), instance and the
  routes that target the interface;
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

## What `compute/manage` already grants

- The VPC, private subnets, private route table, their associations, routes
  on the route tables and the security groups (the NAT's and the
  workspace's), by the `Project` tag.
- The roles `<p>-databricks-cross-account` and `<p>-databricks-uc` and their
  inline policies: its role scoping `<name_root>-<project>-*` covers them. A
  test in `ci-policies` checks this.

So this policy grants no IAM action. Neither role is passed to an AWS service
(Databricks assumes them; `databricks_mws_credentials` and
`databricks_storage_credential` take the ARN through the Databricks API), and
the NAT has no instance profile, so there is no `iam:PassRole`.

## How it is scoped

- **EC2 by tag.** Creating the endpoint, the network interface and the
  Elastic IP requires `aws:RequestTag/Project = <project>`; the endpoint must
  also be for `com.amazonaws.us-east-1.s3`. Every change or delete requires
  `aws:ResourceTag/Project = <project>` on the endpoint, interface, address,
  VPC, subnet, route table or security group it touches.
- **The NAT instance.** `RunInstances` creates an instance only with
  `aws:RequestTag/Project = <project>` and `aws:RequestTag/Component =
  nat-instance` (`StringEquals`) and an `ec2:InstanceType` like `t4g.*`
  (`StringLike`), from an Amazon-owned image, on an existing project network
  interface, subnet and security group. `TerminateInstances` and
  `ModifyInstanceAttribute` require the same two tags on the instance.
  `DetachNetworkInterface`, which `terraform destroy` of the interface calls
  while its attachment is in state, is allowed on project-tagged interfaces
  and instances.
- **The root volume.** The AWS provider applies `root_block_device` tags with
  a `CreateTags` call after launch, so the launch request may carry no volume
  tags. `RunInstances` on a volume is therefore not tag-conditioned (a volume
  exists only with an instance that passed the checks above), and
  `CreateTags` on a volume is allowed when the request sets `Component =
  nat-instance`.
- **Tags on create.** `CreateTags` with `ec2:CreateAction` in
  `CreateVpcEndpoint`, `CreateNetworkInterface`, `AllocateAddress` and
  `RunInstances`, on those resource types only. Tag changes on existing
  resources go through `compute/manage`.
- **Buckets by name.** Configuration of the two buckets. Of their objects,
  only `s3:ListBucket`, `s3:ListBucketVersions`, `s3:DeleteObject` and
  `s3:DeleteObjectVersion`: what `force_destroy` needs to empty them. Never
  `s3:GetObject` or `s3:PutObject`. The catalog bucket's `force_destroy`
  runs after its bucket policy is destroyed, so this grant is what lets a
  plain `terraform destroy` empty it.
- **Credential and event log** as in [`databricks/read`](../read).

## Known gaps

None: no statement uses `Resource = "*"`.

## Known limitations

- Changing the NAT's `instance_type` or metadata options in place is denied:
  this policy grants no `StopInstances`, `StartInstances` or
  `ModifyInstanceMetadataOptions`, and a type change needs a stopped
  instance, so it cannot leave `t4g.*` through `ModifyInstanceAttribute`.
  Replace the instance instead (`terraform apply -replace`); routes follow the
  interface, so egress resumes once the new instance is up.
- `nat-instance` accepts the `t4g`, `c7g`, `c8g` and `m7g` families; this
  policy launches `t4g` only.
- `ec2:DeleteNetworkInterface`, `ec2:DetachNetworkInterface`,
  `ec2:ReleaseAddress` and the other actions on existing resources reach any
  network interface, address or instance tagged with the project, not only
  the NAT's.


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