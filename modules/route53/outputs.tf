output "zone_id" {
  description = "Hosted zone ID — consumed by modules/acm for DNS validation and by ExternalDNS in Phase 2"
  value       = aws_route53_zone.main.zone_id
}

output "zone_arn" {
  description = "Hosted zone ARN"
  value       = aws_route53_zone.main.arn
}

output "name_servers" {
  description = "The four NS records AWS assigned — paste these into your domain registrar's nameserver settings"
  value       = aws_route53_zone.main.name_servers
}
