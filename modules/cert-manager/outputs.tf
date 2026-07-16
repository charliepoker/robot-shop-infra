# modules/cert-manager/outputs.tf

output "iam_role_arn" {
  description = "IAM role ARN bound to the cert-manager service account via Pod Identity"
  value       = aws_iam_role.cert_manager.arn
}

output "iam_policy_arn" {
  value = aws_iam_policy.cert_manager.arn
}
