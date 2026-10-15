mock_provider "aws" {
  override_during = plan

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
      domain_validation_options = [{
        domain_name           = "*.preview.guitar.jwall.engineering"
        resource_record_name  = "_abc.preview.guitar.jwall.engineering."
        resource_record_type  = "CNAME"
        resource_record_value = "_def.acm-validations.aws."
      }]
    }
  }

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      id             = "E1234567890ABC"
      domain_name    = "d111111abcdef8.cloudfront.net"
      hosted_zone_id = "Z2FDTNDATAQYW2"
    }
  }
}

mock_provider "aws" {
  alias           = "wrong_region"
  override_during = plan

  mock_data "aws_region" {
    defaults = {
      region = "us-west-2"
    }
  }
}

variables {
  bucket_name                 = "jwall-engineering-guitar"
  bucket_regional_domain_name = "jwall-engineering-guitar.s3.us-east-1.amazonaws.com"
  site_domain                 = "guitar.jwall.engineering"
  zone_id                     = "Z0123456789ABCDEFGHIJ"
}

run "wildcard_certificate" {
  command = plan

  assert {
    condition     = aws_acm_certificate.this.domain_name == "*.preview.guitar.jwall.engineering" && aws_acm_certificate.this.validation_method == "DNS"
    error_message = "certificate must be a DNS-validated wildcard for *.preview.<site_domain>"
  }

  assert {
    condition     = length(aws_route53_record.validation) == 1 && aws_route53_record.validation["*.preview.guitar.jwall.engineering"].zone_id == "Z0123456789ABCDEFGHIJ"
    error_message = "a validation record must be created in the hosted zone"
  }

  assert {
    condition     = aws_acm_certificate.this.tags["Component"] == "preview-site"
    error_message = "certificate must carry Component = preview-site"
  }
}

run "distribution" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.this.aliases == toset(["*.preview.guitar.jwall.engineering"])
    error_message = "distribution must be aliased to *.preview.<site_domain>"
  }

  assert {
    condition     = one(aws_cloudfront_distribution.this.origin).origin_path == "/previews" && one(aws_cloudfront_distribution.this.origin).domain_name == "jwall-engineering-guitar.s3.us-east-1.amazonaws.com"
    error_message = "origin must serve the bucket under /previews"
  }

  assert {
    condition     = one(aws_cloudfront_distribution.this.default_cache_behavior).viewer_protocol_policy == "redirect-to-https"
    error_message = "HTTP must redirect to HTTPS"
  }

  assert {
    condition     = one(aws_cloudfront_distribution.this.viewer_certificate).minimum_protocol_version == "TLSv1.2_2021" && aws_cloudfront_distribution.this.http_version == "http2and3"
    error_message = "distribution must require TLSv1.2_2021 and enable HTTP/2 and HTTP/3"
  }

  assert {
    condition     = one(one(aws_cloudfront_distribution.this.default_cache_behavior).function_association).event_type == "viewer-request"
    error_message = "the routing function must be attached on viewer-request"
  }

  assert {
    condition     = data.aws_cloudfront_response_headers_policy.security_headers.name == "Managed-SecurityHeadersPolicy"
    error_message = "default behaviour must use the managed SecurityHeadersPolicy"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.tags["Component"] == "preview-site"
    error_message = "distribution must carry Component = preview-site"
  }
}

run "low_ttl_cache_policy" {
  command = plan

  assert {
    condition     = aws_cloudfront_cache_policy.low_ttl.min_ttl == 0 && aws_cloudfront_cache_policy.low_ttl.default_ttl == 60 && aws_cloudfront_cache_policy.low_ttl.max_ttl == 300
    error_message = "cache policy TTLs must be low (0/60/300)"
  }

  assert {
    condition     = aws_cloudfront_cache_policy.low_ttl.name == "jwall-engineering-guitar-preview-low-ttl"
    error_message = "cache policy must be named after the bucket"
  }
}

run "viewer_request_function" {
  command = plan

  assert {
    condition     = aws_cloudfront_function.viewer_request.name == "jwall-engineering-guitar-preview"
    error_message = "function name must be prefixed with bucket_name so site-ci-roles can scope it"
  }

  assert {
    condition     = aws_cloudfront_function.viewer_request.runtime == "cloudfront-js-2.0" && aws_cloudfront_function.viewer_request.publish
    error_message = "function must use the cloudfront-js-2.0 runtime and be published"
  }

  assert {
    condition = (
      can(regex("\\^pr-\\\\d\\+\\$", aws_cloudfront_function.viewer_request.code)) &&
      can(regex("statusCode: 404", aws_cloudfront_function.viewer_request.code)) &&
      can(regex("index\\.html", aws_cloudfront_function.viewer_request.code)) &&
      can(regex("headers\\.host", aws_cloudfront_function.viewer_request.code))
    )
    error_message = "function must read the Host header, enforce ^pr-\\d+$, return 404 otherwise, and rewrite to index.html"
  }
}

run "dns_and_outputs" {
  command = plan

  assert {
    condition = alltrue([
      for t in ["A", "AAAA"] :
      aws_route53_record.alias[t].name == "*.preview.guitar.jwall.engineering"
      && aws_route53_record.alias[t].zone_id == "Z0123456789ABCDEFGHIJ"
      && one(aws_route53_record.alias[t].alias).name == "d111111abcdef8.cloudfront.net"
    ])
    error_message = "wildcard A and AAAA alias records must point at the distribution"
  }

  assert {
    condition     = output.url_pattern == "https://pr-<n>.preview.guitar.jwall.engineering"
    error_message = "url_pattern must be https://pr-<n>.preview.<site_domain>"
  }

  assert {
    condition     = output.distribution_id == "E1234567890ABC"
    error_message = "distribution_id must come from the distribution"
  }
}

run "refuses_other_regions" {
  command = plan

  providers = {
    aws = aws.wrong_region
  }

  expect_failures = [aws_acm_certificate.this]
}

run "rejects_bad_site_domain" {
  command = plan

  variables {
    site_domain = "*.guitar.jwall.engineering"
  }

  expect_failures = [var.site_domain]
}
