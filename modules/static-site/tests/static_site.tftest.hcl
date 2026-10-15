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
        domain_name           = "guitar.jwall.engineering"
        resource_record_name  = "_abc.guitar.jwall.engineering."
        resource_record_type  = "CNAME"
        resource_record_value = "_def.acm-validations.aws."
      }]
    }
  }

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      id             = "E1234567890ABC"
      arn            = "arn:aws:cloudfront::123456789012:distribution/E1234567890ABC"
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
      region = "eu-west-1"
    }
  }
}

variables {
  bucket_name                 = "jwall-engineering-guitar"
  bucket_regional_domain_name = "jwall-engineering-guitar.s3.us-east-1.amazonaws.com"
  origin_path                 = "/prod"
  domain_name                 = "guitar.jwall.engineering"
  zone_id                     = "Z0123456789ABCDEFGHIJ"
}

run "certificate" {
  command = plan

  assert {
    condition     = aws_acm_certificate.this.domain_name == "guitar.jwall.engineering" && aws_acm_certificate.this.validation_method == "DNS"
    error_message = "certificate must be DNS-validated for domain_name"
  }

  assert {
    condition     = length(aws_route53_record.validation) == 1 && aws_route53_record.validation["guitar.jwall.engineering"].zone_id == "Z0123456789ABCDEFGHIJ"
    error_message = "a validation record must be created in the hosted zone"
  }

  assert {
    condition     = aws_acm_certificate.this.tags["Component"] == "static-site"
    error_message = "certificate must carry Component = static-site"
  }
}

run "distribution" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.this.aliases == toset(["guitar.jwall.engineering"])
    error_message = "distribution must be aliased to domain_name"
  }

  assert {
    condition     = one(aws_cloudfront_distribution.this.default_cache_behavior).viewer_protocol_policy == "redirect-to-https"
    error_message = "HTTP must redirect to HTTPS"
  }

  assert {
    condition     = one(aws_cloudfront_distribution.this.viewer_certificate).minimum_protocol_version == "TLSv1.2_2021" && one(aws_cloudfront_distribution.this.viewer_certificate).ssl_support_method == "sni-only"
    error_message = "viewer certificate must require TLSv1.2_2021 with SNI"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.http_version == "http2and3" && aws_cloudfront_distribution.this.is_ipv6_enabled
    error_message = "distribution must enable HTTP/2, HTTP/3 and IPv6"
  }

  # Managed policy IDs are optional+computed on the data sources, so the mock
  # provider cannot fill them in during plan. Check the lookups by name instead.
  assert {
    condition     = data.aws_cloudfront_cache_policy.caching_optimized.name == "Managed-CachingOptimized"
    error_message = "default behaviour must use the managed CachingOptimized policy"
  }

  assert {
    condition     = data.aws_cloudfront_response_headers_policy.security_headers.name == "Managed-SecurityHeadersPolicy"
    error_message = "default behaviour must use the managed SecurityHeadersPolicy"
  }

  assert {
    condition     = one(one(aws_cloudfront_distribution.this.default_cache_behavior).function_association).event_type == "viewer-request"
    error_message = "the rewrite function must be attached on viewer-request"
  }

  assert {
    condition = alltrue([
      for e in aws_cloudfront_distribution.this.custom_error_response :
      e.response_page_path == "/404.html" && e.response_code == 404
    ]) && toset([for e in aws_cloudfront_distribution.this.custom_error_response : e.error_code]) == toset([403, 404])
    error_message = "403 and 404 must both serve /404.html with status 404"
  }

  assert {
    condition     = one(aws_cloudfront_distribution.this.origin).origin_path == "/prod" && one(aws_cloudfront_distribution.this.origin).domain_name == "jwall-engineering-guitar.s3.us-east-1.amazonaws.com"
    error_message = "origin must point at the bucket's regional domain under origin_path"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.tags["Component"] == "static-site"
    error_message = "distribution must carry Component = static-site"
  }
}

run "origin_access_control_and_function" {
  command = plan

  assert {
    condition     = aws_cloudfront_origin_access_control.this.origin_access_control_origin_type == "s3" && aws_cloudfront_origin_access_control.this.signing_behavior == "always" && aws_cloudfront_origin_access_control.this.signing_protocol == "sigv4"
    error_message = "OAC must sign every S3 request with sigv4"
  }

  assert {
    condition     = aws_cloudfront_function.viewer_request.name == "jwall-engineering-guitar-guitar-jwall-engineering"
    error_message = "function name must be prefixed with bucket_name so the static-site/* CI policies can scope it (got ${aws_cloudfront_function.viewer_request.name})"
  }

  assert {
    condition     = aws_cloudfront_function.viewer_request.runtime == "cloudfront-js-2.0" && aws_cloudfront_function.viewer_request.publish
    error_message = "function must use the cloudfront-js-2.0 runtime and be published"
  }

  assert {
    condition     = can(regex("index\\.html", aws_cloudfront_function.viewer_request.code))
    error_message = "function must rewrite to index.html"
  }
}

run "dns_and_outputs" {
  command = plan

  assert {
    condition = alltrue([
      for t in ["A", "AAAA"] :
      aws_route53_record.alias[t].name == "guitar.jwall.engineering" && aws_route53_record.alias[t].zone_id == "Z0123456789ABCDEFGHIJ"
      && one(aws_route53_record.alias[t].alias).name == "d111111abcdef8.cloudfront.net"
      && one(aws_route53_record.alias[t].alias).zone_id == "Z2FDTNDATAQYW2"
    ])
    error_message = "A and AAAA alias records must point at the distribution"
  }

  assert {
    condition     = output.url == "https://guitar.jwall.engineering"
    error_message = "url output must be https://<domain_name>"
  }

  assert {
    condition     = output.distribution_id == "E1234567890ABC" && output.distribution_arn == "arn:aws:cloudfront::123456789012:distribution/E1234567890ABC"
    error_message = "distribution outputs must come from the distribution"
  }
}

run "refuses_other_regions" {
  command = plan

  providers = {
    aws = aws.wrong_region
  }

  # The distribution depends on the certificate, so only the certificate's
  # precondition is evaluated once that one fails.
  expect_failures = [aws_acm_certificate.this]
}

run "rejects_origin_path_without_leading_slash" {
  command = plan

  variables {
    origin_path = "prod/"
  }

  expect_failures = [var.origin_path]
}

run "rejects_bad_domain_name" {
  command = plan

  variables {
    domain_name = "Guitar.JWall.Engineering."
  }

  expect_failures = [var.domain_name]
}
