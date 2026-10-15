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
        domain_name           = "validation"
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

variables {
  bucket_name                 = "jwall-engineering-guitar"
  bucket_regional_domain_name = "jwall-engineering-guitar.s3.us-east-1.amazonaws.com"
  domain_name                 = "guitar.jwall.engineering"
  zone_id                     = "Z0123456789ABCDEFGHIJ"
}

run "prod_and_preview_by_default" {
  command = plan

  assert {
    condition     = output.prod_url == "https://guitar.jwall.engineering"
    error_message = "prod must be served on domain_name"
  }

  assert {
    condition     = one(module.prod.distribution_id[*]) != null && length(module.dev) == 0 && length(module.preview) == 1
    error_message = "defaults must create prod and preview but no dev"
  }

  assert {
    condition     = output.dev_url == null && output.dev_distribution_id == null
    error_message = "dev outputs must be null without dev_domain_name"
  }

  assert {
    condition     = output.preview_url_pattern == "https://pr-<n>.preview.guitar.jwall.engineering"
    error_message = "preview must be served on *.preview.<domain_name>"
  }

  assert {
    condition     = keys(output.distribution_ids) == ["preview", "prod"]
    error_message = "distribution_ids must list prod and preview only"
  }
}

run "origin_paths" {
  command = plan

  variables {
    dev_domain_name = "dev.guitar.jwall.engineering"
  }

  assert {
    condition     = one(module.prod.distribution_id[*]) != null && length(module.dev) == 1
    error_message = "dev_domain_name must create the dev distribution"
  }

  assert {
    condition     = output.dev_url == "https://dev.guitar.jwall.engineering"
    error_message = "dev must be served on dev_domain_name"
  }

  assert {
    condition     = keys(output.distribution_ids) == ["dev", "preview", "prod"]
    error_message = "distribution_ids must include dev, preview and prod"
  }
}

run "preview_can_be_disabled" {
  command = plan

  variables {
    enable_preview = false
  }

  assert {
    condition     = length(module.preview) == 0 && output.preview_url_pattern == null && output.preview_distribution_id == null
    error_message = "enable_preview = false must skip the preview distribution"
  }
}

run "rejects_bad_dev_domain" {
  command = plan

  variables {
    dev_domain_name = "Dev.Guitar"
  }

  expect_failures = [var.dev_domain_name]
}
