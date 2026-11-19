# service-linked-role

One IAM service-linked role: the role an AWS service assumes to act in the
account on your behalf. AWS names it and fixes its permissions; you only choose
the service. The motivating case is `spot.amazonaws.com`
(`AWSServiceRoleForEC2Spot`): EC2 needs it before the first Spot launch in an
account. EC2 creates it on that launch only if the caller may call
`iam:CreateServiceLinkedRole`, and a task launch role should not be able to.
Without it, the launch fails with `AuthFailure.ServiceLinkedRoleCreationNotPermitted`.

- **Once per account.** An account holds one service-linked role per service,
  so create it from an account-level stack (the foundation), never from a
  per-project one. A second project's stack would collide with the first,
  and destroying either would take the role from the other.
- **Tagged `Component`**, like every module here. IAM accepts tags on
  service-linked roles, so the provider's `default_tags` apply too. The caller
  needs `iam:TagRole` on the role. The `foundation/manage` policy grants it,
  with `service_linked_role_services`.

## `prevent_destroy` is hard-coded

The role carries `lifecycle { prevent_destroy = true }`. Terraform does not
allow lifecycle arguments to come from variables. A service that still uses
its role refuses the deletion anyway, and one that doesn't would quietly lose
the role it needs on its next launch. To stop managing the role, remove it from
state (or use a `removed` block with `destroy = false`).

## Adopting an existing role

IAM refuses a second role for the same service. In an account that already
has the role (because a service created it), import it instead:

```hcl
import {
  to = module.spot_role.aws_iam_service_linked_role.this
  id = "arn:aws:iam::<account>:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot"
}
```

Set `description` to the role's current description
(`aws iam get-role --role-name <name> --query Role.Description`) so the
import plans no change to it. EC2 gives its Spot role
`Default EC2 Spot Service Linked Role`.

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
| [aws_iam_service_linked_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_service_linked_role) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| aws\_service\_name | The service principal the role is linked to, for example `spot.amazonaws.com` (`AWSServiceRoleForEC2Spot`, which EC2 needs before the first Spot launch in an account). | `string` | n/a | yes |
| component | Value of the `Component` tag on the role. | `string` | `"iam"` | no |
| description | The role's description. Set it to an existing role's current description to adopt the role without a change; `null` leaves it unset. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | The role's ARN, `arn:aws:iam::<account>:role/aws-service-role/<service>/<name>`. |
| name | The role's name, which AWS chooses per service (for example `AWSServiceRoleForEC2Spot`). |
<!-- END_TF_DOCS -->
