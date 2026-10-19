resource "aws_route53_zone" "this" {
  name    = var.name
  comment = var.comment

  tags = {
    Name      = coalesce(var.name_tag, var.name)
    Component = var.component
  }

  # Hard-coded: lifecycle arguments cannot come from variables. Deleting the
  # zone breaks every record in it and changes its name servers, so the module
  # never allows it.
  lifecycle {
    prevent_destroy = true
  }
}

# Zone-level CAA record. Project repos own every record in the zone except
# this one and the TXT records below.
resource "aws_route53_record" "caa" {
  count = length(var.caa_issuers) > 0 ? 1 : 0

  zone_id = aws_route53_zone.this.zone_id
  name    = var.name
  type    = "CAA"
  ttl     = var.caa_ttl

  records = [for issuer in var.caa_issuers : "0 issue \"${issuer}\""]
}

# Zone-level TXT records: domain-verification tokens and the like that belong
# to the zone owner, not to a project. Values are passed bare: the AWS
# provider wraps each TXT string in the double quotes Route 53 wants and
# strips them again on read, so quoting here would double them and Route 53
# would reject the change.
resource "aws_route53_record" "txt" {
  for_each = var.txt_records

  zone_id = aws_route53_zone.this.zone_id
  name    = each.key == "@" ? var.name : "${each.key}.${var.name}"
  type    = "TXT"
  ttl     = var.txt_ttl

  records = each.value
}
