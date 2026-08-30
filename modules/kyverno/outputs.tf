# modules/kyverno/outputs.tf

output "iam_role_arn" {
  description = "IAM role ARN bound to the Kyverno admission-controller service account via Pod Identity"
  value       = aws_iam_role.kyverno.arn
}

output "iam_role_name" {
  description = "Kyverno IAM role name"
  value       = aws_iam_role.kyverno.name
}
