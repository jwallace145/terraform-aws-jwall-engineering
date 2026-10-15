output "zone_id" {
  description = "Hosted zone ID, for `zone_id` of `site-ci-roles`, `static-site` and the root site stack."
  value       = aws_route53_zone.this.zone_id
}

output "arn" {
  description = "Hosted zone ARN, for `hosted_zone_arn` of `infra-ci-roles`."
  value       = aws_route53_zone.this.arn
}

output "name" {
  description = "Zone name."
  value       = aws_route53_zone.this.name
}

output "name_servers" {
  description = "Name servers to delegate the domain to at its registrar."
  value       = aws_route53_zone.this.name_servers
}
