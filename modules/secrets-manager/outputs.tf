output "secret_arn" {
  description = <<-EOT
    RDS credentials secret ARN.
    Used in Phase 2 ESO ClusterSecretStore to grant read access:
      spec:
        provider:
          aws:
            service: SecretsManager
            region: us-east-1
    And in the ExternalSecret remoteRef:
      remoteRef:
        key: robot-shop/rds-credentials
  EOT
  value = aws_secretsmanager_secret.rds.arn
}

output "secret_name" {
  description = "Secret name path — used in ExternalSecret remoteRef.key"
  value       = aws_secretsmanager_secret.rds.name
}

output "secret_version_id" {
  description = "Current version ID of the secret"
  value       = aws_secretsmanager_secret_version.rds.version_id
}
