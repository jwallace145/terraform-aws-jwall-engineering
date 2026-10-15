# static-site

Serves one environment of a static site from a prefix of the project's bucket
through CloudFront. Project repos call this module once per environment
(`prod`, `dev`, ...).

## What it creates

- An ACM certificate for `domain_name`, validated through Route 53 DNS.
- A CloudFront origin access control (OAC) for the S3 origin.
- A CloudFront distribution that:
  - serves `bucket_regional_domain_name` at `origin_path` (for example `/prod`)
  - redirects HTTP to HTTPS, requires `TLSv1.2_2021`, enables HTTP/2 and HTTP/3
  - uses the managed `CachingOptimized` cache policy and the managed
    `SecurityHeadersPolicy` response headers policy
  - serves `/404.html` with status 404 for missing objects. S3 returns 403 for
    missing keys when the viewer only has `GetObject`, so both 403 and 404 are
    mapped to the custom error page.
- A viewer-request CloudFront Function that rewrites `/dir/` to
  `/dir/index.html` (and `/dir` without an extension to `/dir/index.html`).
- Route 53 `A` and `AAAA` alias records for `domain_name`.

Everything runs in `us-east-1`; the module has a precondition that fails the
plan in any other region.

Every resource is tagged `Component = "static-site"`. All other tags come from
the caller's provider `default_tags` (see the `context` module). The `Project`
tag from `default_tags` is what the `static-site/*` CI policies in
`ci-policies` use to authorise changes to these resources.

The CloudFront Function is named `<bucket_name>-<domain-with-dashes>`,
truncated to 64 characters, so that it matches the
`jwall-engineering-<project>-*` name scope of the `static-site/*` CI policies.

On the registry: <https://registry.terraform.io/modules/jwallace145/jwall-engineering/aws/latest/submodules/static-site>

## Usage

```hcl
module "context" {
  source  = "jwallace145/jwall-engineering/aws//modules/context"
  version = "~> 0.1"
  project     = "guitar"
  environment = "prod"
  repository  = "jwallace145/guitar"
}

provider "aws" {
  region = "us-east-1"
  default_tags { tags = module.context.tags }
}

module "prod" {
  source  = "jwallace145/jwall-engineering/aws//modules/static-site"
  version = "~> 0.1"

  bucket_name                 = module.context.bucket_name
  bucket_regional_domain_name = "${module.context.bucket_name}.s3.us-east-1.amazonaws.com"
  origin_path                 = "/prod"
  domain_name                 = "guitar.jwall.engineering"
  zone_id                     = "Z0123456789ABCDEFGHIJ"
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
| [aws_acm_certificate.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate) | resource |
| [aws_acm_certificate_validation.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation) | resource |
| [aws_cloudfront_distribution.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution) | resource |
| [aws_cloudfront_function.viewer_request](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_function) | resource |
| [aws_cloudfront_origin_access_control.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_control) | resource |
| [aws_route53_record.alias](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_cloudfront_cache_policy.caching_optimized](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/cloudfront_cache_policy) | data source |
| [aws_cloudfront_response_headers_policy.security_headers](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/cloudfront_response_headers_policy) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| bucket\_name | Name of the project's site bucket (output `name` of `site-bucket`, or `bucket_name` of `context`). Also used as the prefix of the CloudFront Function name. | `string` | n/a | yes |
| bucket\_regional\_domain\_name | Regional domain name of the site bucket (output `regional_domain_name` of `site-bucket`), used as the distribution origin. | `string` | n/a | yes |
| domain\_name | FQDN the site is served on, for example `guitar.jwall.engineering`. An ACM certificate is issued for exactly this name. | `string` | n/a | yes |
| origin\_path | Prefix inside the bucket this environment is served from, for example `/prod` or `/dev`. Must start with `/` and not end with one. | `string` | n/a | yes |
| zone\_id | Route 53 hosted zone ID that contains `domain_name`. Validation and alias records are created in it. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| distribution\_arn | CloudFront distribution ARN. |
| distribution\_id | CloudFront distribution ID (use for `aws cloudfront create-invalidation`). |
| url | Public URL of the site (`https://<domain_name>`). |
<!-- END_TF_DOCS -->
