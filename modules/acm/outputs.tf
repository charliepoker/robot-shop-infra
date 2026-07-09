output "certificate_arn" {
  description = <<-EOT
    Validated wildcard certificate ARN.
    This output comes from aws_acm_certificate_validation, not
    aws_acm_certificate — which means it is only populated once the
    cert is actually ISSUED, not just requested.
    Referenced in Phase 2 ALB Ingress annotations:
      alb.ingress.kubernetes.io/certificate-arn: <this value>
  EOT
  value       = aws_acm_certificate_validation.wildcard.certificate_arn
}

output "certificate_domain" {
  description = "Primary domain of the certificate"
  value       = aws_acm_certificate.wildcard.domain_name
}

output "certificate_status" {
  description = "Current status of the certificate — should be ISSUED after apply"
  value       = aws_acm_certificate.wildcard.status
}
