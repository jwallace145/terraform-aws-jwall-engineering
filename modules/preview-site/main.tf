data "aws_region" "current" {}

data "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "Managed-SecurityHeadersPolicy"
}

locals {
  component = "preview-site"

  region_ok      = data.aws_region.current.region == "us-east-1"
  region_message = "preview-site must be deployed in us-east-1 (CloudFront certificates live there); the current region is ${data.aws_region.current.region}."

  preview_domain  = "preview.${var.site_domain}"
  wildcard_domain = "*.${local.preview_domain}"
  origin_path     = "/previews"

  # Prefixed with the bucket name (jwall-engineering-<project>) so that
  # site-ci-roles can scope function permissions by name.
  function_name     = substr("${var.bucket_name}-preview", 0, 64)
  cache_policy_name = substr("${var.bucket_name}-preview-low-ttl", 0, 128)

  origin_id = "s3-${var.bucket_name}-previews"

  tags = {
    Component = local.component
  }
}

# --- TLS certificate -------------------------------------------------------

resource "aws_acm_certificate" "this" {
  domain_name       = local.wildcard_domain
  validation_method = "DNS"

  tags = local.tags

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = local.region_ok
      error_message = local.region_message
    }
  }
}

resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = var.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}

# --- CloudFront ------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.bucket_name}${local.origin_path}"
  description                       = "OAC for ${local.wildcard_domain}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Previews change on every push, so keep edge caching short.
resource "aws_cloudfront_cache_policy" "low_ttl" {
  name        = local.cache_policy_name
  comment     = "Low-TTL cache policy for ${local.wildcard_domain}"
  min_ttl     = 0
  default_ttl = 60
  max_ttl     = 300

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_function" "viewer_request" {
  name    = local.function_name
  runtime = "cloudfront-js-2.0"
  comment = "Route pr-<n>.${local.preview_domain} to previews/pr-<n>/"
  publish = true
  code    = file("${path.module}/functions/viewer-request.js")

  tags = local.tags
}

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  comment         = local.wildcard_domain
  aliases         = [local.wildcard_domain]
  is_ipv6_enabled = true
  http_version    = "http2and3"
  price_class     = "PriceClass_100"

  origin {
    origin_id                = local.origin_id
    domain_name              = var.bucket_regional_domain_name
    origin_path              = local.origin_path
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = aws_cloudfront_cache_policy.low_ttl.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.viewer_request.arn
    }
  }

  # The function rewrites every URI under /pr-<n>/, so a missing preview or
  # page surfaces as 403/404 from S3; both map to that preview's 404 page
  # which the function has already rewritten into the pr-<n>/ folder.
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.this.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition     = local.region_ok
      error_message = local.region_message
    }
  }
}

# --- DNS -------------------------------------------------------------------

resource "aws_route53_record" "alias" {
  for_each = toset(["A", "AAAA"])

  zone_id = var.zone_id
  name    = local.wildcard_domain
  type    = each.key

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
