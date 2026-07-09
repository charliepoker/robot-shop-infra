output "role_arn" {
  description = <<-EOT
    GitHub Actions IAM role ARN.
    Add this as a repository secret in charliepoker/robot-shop:
      Settings → Secrets and variables → Actions → New repository secret
      Name:  AWS_ROLE_ARN
      Value: <this output>
    The CI workflow references it as:
      role-to-assume: $${{ secrets.AWS_ROLE_ARN }}
  EOT
  value       = aws_iam_role.github_actions.arn
}

output "role_name" {
  description = "GitHub Actions IAM role name"
  value       = aws_iam_role.github_actions.name
}

output "oidc_provider_arn" {
  description = "GitHub OIDC provider ARN registered in this AWS account"
  value       = aws_iam_openid_connect_provider.github.arn
}
