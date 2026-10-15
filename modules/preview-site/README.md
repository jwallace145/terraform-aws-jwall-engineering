# preview-site

Serves pull-request previews of a static site from `pr-<n>.preview.<site_domain>`.
Project repos call this module once per project; the `ci-preview` role uploads
each PR's build to `previews/pr-<n>/` in the site bucket and this distribution
routes the matching subdomain to it.

## What it creates

- A wildcard ACM certificate for `*.preview.<site_domain>`, DNS-validated.
- A CloudFront origin access control for the S3 origin.
- A custom cache policy with low TTLs (min 0s, default 60s, max 300s) so new
  pushes show up quickly without invalidations.
- A CloudFront distribution aliased to `*.preview.<site_domain>` with origin
  path `/previews`, HTTP to HTTPS redirect, `TLSv1.2_2021`, HTTP/2 and HTTP/3,
  the managed security-headers policy and `/404.html` for 403/404.
- A viewer-request CloudFront Function that:
  1. extracts the first label of the `Host` header
  2. returns `404` unless that label matches `^pr-\d+$`
  3. otherwise rewrites the URI to `/<label><uri>`, applying the same
     `index.html` rewrite as `static-site` (`/dir/` and `/dir` become
     `/dir/index.html`)
- Wildcard Route 53 `A` and `AAAA` alias records for `*.preview.<site_domain>`.

Everything runs in `us-east-1`; the module has a precondition that fails the
plan in any other region.

Every resource is tagged `Component = "preview-site"`. All other tags come from
the caller's provider `default_tags` (see the `context` module). The function
is named `<bucket_name>-preview` so that it matches the
`jwall-engineering-<project>-*` name scope in `site-ci-roles`.

## Usage

```hcl
module "preview" {
  source = "git::https://github.com/jwallace145/terraform-library.git//modules/preview-site?ref=v0.1.0"

  bucket_name                 = module.context.bucket_name
  bucket_regional_domain_name = "${module.context.bucket_name}.s3.us-east-1.amazonaws.com"
  site_domain                 = "guitar.jwall.engineering"
  zone_id                     = "Z0123456789ABCDEFGHIJ"
}
```

A PR workflow then publishes with the `ci-preview` role:

```sh
aws s3 sync ./dist "s3://jwall-engineering-guitar/previews/pr-${PR_NUMBER}/" --delete
echo "https://pr-${PR_NUMBER}.preview.guitar.jwall.engineering"
```

Objects under `previews/` expire after 14 days (see `site-bucket`).

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
| [aws_cloudfront_cache_policy.low_ttl](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_cache_policy) | resource |
| [aws_cloudfront_distribution.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution) | resource |
| [aws_cloudfront_function.viewer_request](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_function) | resource |
| [aws_cloudfront_origin_access_control.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_control) | resource |
| [aws_route53_record.alias](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_cloudfront_response_headers_policy.security_headers](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/cloudfront_response_headers_policy) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| bucket\_name | Name of the project's site bucket (output `name` of `site-bucket`, or `bucket_name` of `context`). Also used as the prefix of the CloudFront Function name. | `string` | n/a | yes |
| bucket\_regional\_domain\_name | Regional domain name of the site bucket (output `regional_domain_name` of `site-bucket`), used as the distribution origin. | `string` | n/a | yes |
| site\_domain | The site's production FQDN, for example `guitar.jwall.engineering`. Previews are served from `pr-<n>.preview.<site_domain>`. | `string` | n/a | yes |
| zone\_id | Route 53 hosted zone ID that contains `site_domain`. Validation and wildcard alias records are created in it. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| distribution\_id | CloudFront distribution ID serving `*.preview.<site_domain>`. |
| url\_pattern | URL pattern for previews: `https://pr-<n>.preview.<site_domain>`. |
<!-- END_TF_DOCS -->
