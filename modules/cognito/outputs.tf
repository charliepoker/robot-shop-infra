output "user_pool_id" {
  description = "User pool ID, used to create users with the CLI"
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  description = "User pool ARN for the ALB auth-idp-cognito annotation"
  value       = aws_cognito_user_pool.this.arn
}

output "user_pool_client_id" {
  description = "App client ID for the ALB auth-idp-cognito annotation. Not a secret."
  value       = aws_cognito_user_pool_client.alb.id
}

output "user_pool_domain" {
  description = "Hosted UI domain prefix for the ALB auth-idp-cognito annotation"
  value       = aws_cognito_user_pool_domain.this.domain
}

output "hosted_ui_url" {
  description = "Base URL of the Cognito sign-in page"
  value       = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${data.aws_region.current.region}.amazoncognito.com"
}

output "alb_auth_idp_cognito" {
  description = "Ready-to-paste value for the alb.ingress.kubernetes.io/auth-idp-cognito annotation"
  value = jsonencode({
    userPoolARN      = aws_cognito_user_pool.this.arn
    userPoolClientID = aws_cognito_user_pool_client.alb.id
    userPoolDomain   = aws_cognito_user_pool_domain.this.domain
  })
}
