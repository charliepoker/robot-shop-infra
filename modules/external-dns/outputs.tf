# modules/external-dns/outputs.tf

output "iam_role_arn" {
  description = "IAM role ARN bound to the ExternalDNS service account via Pod Identity"
  value       = aws_iam_role.external_dns.arn
}

output "iam_policy_arn" {
  value = aws_iam_policy.external_dns.arn
}
