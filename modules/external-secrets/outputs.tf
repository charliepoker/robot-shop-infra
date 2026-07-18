output "iam_role_arn" {
  description = "IAM role ARN bound to the ESO controller service account via Pod Identity"
  value       = aws_iam_role.external_secrets.arn
}

output "iam_policy_arn" {
  value = aws_iam_policy.external_secrets.arn
}
