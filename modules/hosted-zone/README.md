# hosted-zone

A public Route 53 hosted zone and its zone-level CAA record. The infra repo
owns the zone; project repos own the records inside it. Use `comment` to say
so, because the comment is what someone sees first in the console.

- The zone is tagged `Name` and `Component`. `Name` is the zone name unless
  `name_tag` is set.
- When `caa_issuers` is not empty, the module creates one CAA record at the
  zone apex with a `0 issue "<issuer>"` value per issuer. The default is the
  four Amazon CAs that ACM needs. An empty list creates no CAA record.

## `prevent_destroy` is hard-coded

The zone carries `lifecycle { prevent_destroy = true }`. Terraform does not
allow lifecycle arguments to come from variables, so this cannot be turned
off by an input. Deleting a zone removes every record in it, and a recreated
zone gets new name servers that the registrar does not know about. To remove
the zone on purpose, remove it from state first.

## Adopting an existing zone

To bring a zone that is already in state under this module, add `moved`
blocks to the module's addresses and pass the zone's current `Name` tag as
`name_tag`:

```hcl
moved {
  from = aws_route53_zone.this
  to   = module.zone.aws_route53_zone.this
}

moved {
  from = aws_route53_record.caa
  to   = module.zone.aws_route53_record.caa[0]
}
```

To adopt a zone that is not in any state yet, import it to
`module.zone.aws_route53_zone.this`.

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/hosted-zone>

## Usage

```hcl
module "zone" {
  source  = "jwallace145/jwall-engineering/aws//modules/hosted-zone"
  version = "~> 0.4"

  name    = "jwall.engineering"
  comment = "jwall-engineering: zone owned by jwallace145/jwall-engineering-infra; records owned by project repos"
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
| [aws_route53_record.caa](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_zone.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| comment | Zone comment. State who owns the zone and who owns its records, for example `zone owned by owner/infra; records owned by project repos`. | `string` | n/a | yes |
| name | Zone name as a lowercase FQDN without a trailing dot, for example `jwall.engineering`. | `string` | n/a | yes |
| caa\_issuers | Certificate authorities allowed to issue for the zone and its subdomains, as CAA `issue` domains. The default is the four Amazon CAs that ACM needs. An empty list creates no CAA record. | `list(string)` | <pre>[<br/>  "amazon.com",<br/>  "amazontrust.com",<br/>  "awstrust.com",<br/>  "amazonaws.com"<br/>]</pre> | no |
| caa\_ttl | TTL in seconds of the CAA record. | `number` | `300` | no |
| component | Value of the `Component` tag on the zone. | `string` | `"dns"` | no |
| name\_tag | Value of the zone's `Name` tag. Left `null`, it falls back to `name`. Set it to an existing zone's current `Name` tag to adopt the zone without a tag change. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | Hosted zone ARN, for `policy_inputs.foundation.hosted_zone_arn` of the CI role modules. |
| name | Zone name. |
| name\_servers | Name servers to delegate the domain to at its registrar. |
| zone\_id | Hosted zone ID, for `policy_inputs.static_site.zone_id` of the CI role modules, `static-site` and the root site stack. |
<!-- END_TF_DOCS -->
