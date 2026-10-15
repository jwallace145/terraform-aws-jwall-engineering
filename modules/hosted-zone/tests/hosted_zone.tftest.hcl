mock_provider "aws" {
  override_during = plan

  mock_resource "aws_route53_zone" {
    defaults = {
      zone_id      = "Z0123456789ABCDEFGHIJ"
      arn          = "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ"
      name_servers = ["ns-1.awsdns-01.org", "ns-2.awsdns-02.com"]
    }
  }
}

variables {
  name    = "jwall.engineering"
  comment = "jwall-engineering: zone owned by jwallace145/jwall-engineering-infra; records owned by project repos"
}

run "zone_passes_name_and_comment_through" {
  command = plan

  assert {
    condition     = aws_route53_zone.this.name == "jwall.engineering"
    error_message = "zone name must be var.name"
  }

  assert {
    condition     = aws_route53_zone.this.comment == var.comment
    error_message = "zone comment must be var.comment"
  }
}

run "tags_default_name_to_zone_name" {
  command = plan

  assert {
    condition     = aws_route53_zone.this.tags == tomap({ Name = "jwall.engineering", Component = "dns" })
    error_message = "without name_tag, Name falls back to the zone name and Component is dns"
  }
}

run "name_tag_overrides_name" {
  command = plan

  variables {
    name_tag = "jwall-engineering-infra-dns-zone"
  }

  assert {
    condition     = aws_route53_zone.this.tags["Name"] == "jwall-engineering-infra-dns-zone"
    error_message = "name_tag must set the Name tag"
  }
}

run "default_caa_allows_amazon_issuers" {
  command = plan

  assert {
    condition = aws_route53_record.caa[0].records == toset([
      "0 issue \"amazon.com\"",
      "0 issue \"amazontrust.com\"",
      "0 issue \"awstrust.com\"",
      "0 issue \"amazonaws.com\"",
    ])
    error_message = "the default CAA issuers are the four Amazon CAs ACM needs"
  }
}

run "caa_record_for_two_issuers" {
  command = plan

  variables {
    caa_issuers = ["amazon.com", "letsencrypt.org"]
  }

  assert {
    condition     = length(aws_route53_record.caa) == 1
    error_message = "a non-empty issuer list creates one CAA record"
  }

  assert {
    condition = (
      aws_route53_record.caa[0].type == "CAA" &&
      aws_route53_record.caa[0].name == "jwall.engineering" &&
      aws_route53_record.caa[0].ttl == 300 &&
      aws_route53_record.caa[0].zone_id == "Z0123456789ABCDEFGHIJ"
    )
    error_message = "the CAA record must sit at the zone apex with TTL 300"
  }

  assert {
    condition     = aws_route53_record.caa[0].records == toset(["0 issue \"amazon.com\"", "0 issue \"letsencrypt.org\""])
    error_message = "each issuer must become a quoted `0 issue \"<issuer>\"` value"
  }
}

run "no_caa_record_for_empty_list" {
  command = plan

  variables {
    caa_issuers = []
  }

  assert {
    condition     = length(aws_route53_record.caa) == 0
    error_message = "an empty issuer list creates no CAA record"
  }
}

run "caa_ttl_is_configurable" {
  command = plan

  variables {
    caa_ttl = 3600
  }

  assert {
    condition     = aws_route53_record.caa[0].ttl == 3600
    error_message = "caa_ttl must set the CAA record TTL"
  }
}

run "outputs" {
  command = plan

  assert {
    condition = (
      output.zone_id == "Z0123456789ABCDEFGHIJ" &&
      output.arn == "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ" &&
      output.name == "jwall.engineering" &&
      output.name_servers == tolist(["ns-1.awsdns-01.org", "ns-2.awsdns-02.com"])
    )
    error_message = "outputs must describe the zone"
  }
}

run "rejects_trailing_dot" {
  command = plan

  variables {
    name = "jwall.engineering."
  }

  expect_failures = [var.name]
}

run "rejects_empty_comment" {
  command = plan

  variables {
    comment = ""
  }

  expect_failures = [var.comment]
}

run "rejects_quoted_issuer" {
  command = plan

  variables {
    caa_issuers = ["\"amazon.com\""]
  }

  expect_failures = [var.caa_issuers]
}
