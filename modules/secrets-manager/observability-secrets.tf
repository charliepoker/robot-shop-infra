###############################################################################
# Observability credentials
#
# Phase 5 Task 1. Grafana admin login, generated here and stored in Secrets
# Manager so it never appears in Git or in Helm values. External Secrets
# Operator projects it into the monitoring namespace as monitoring/grafana-admin.
#
# Self contained like app-db-secrets.tf: resources and outputs live here so the
# file drops into the module without editing existing files. It reuses the
# module's existing variables (name_prefix, environment, kms_key_id,
# recovery_window_in_days) and the random provider already pinned in
# versions.tf.
#
# Phase 5 Task 5 adds the Alertmanager Slack webhook to this file. That one
# cannot be generated, so it will be created empty and its value set out of
# band.
###############################################################################

# -----------------------------------------------------------------------------
# Generated password
#
# Alphanumeric only: 32 chars from [A-Za-z0-9] is ~190 bits of entropy, and it
# survives copy/paste, shell quoting and the Grafana login form without any
# escaping surprises.
# -----------------------------------------------------------------------------

resource "random_password" "grafana_admin" {
  length      = 32
  special     = false
  min_lower   = 4
  min_upper   = 4
  min_numeric = 4
}

# -----------------------------------------------------------------------------
# Secret
#
# Description is single line ASCII on purpose. AWS rejects tabs, newlines and
# em dashes in this field.
# -----------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "grafana_admin" {
  name                    = "${var.name_prefix}/grafana-admin"
  description             = "Grafana admin credentials for the robot-shop observability stack"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = {
    Name        = "${var.name_prefix}/grafana-admin"
    Environment = var.environment
    Component   = "observability"
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "grafana_admin" {
  secret_id = aws_secretsmanager_secret.grafana_admin.id

  secret_string = jsonencode({
    GRAFANA_ADMIN_USER     = "admin"
    GRAFANA_ADMIN_PASSWORD = random_password.grafana_admin.result
  })

  # Terraform seeds the credential, then stops managing its value, so an
  # out-of-band rotation is never silently reverted by the next apply.
  # Same reasoning as the per-service DB secrets in app-db-secrets.tf.
  lifecycle {
    ignore_changes = [secret_string]
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "grafana_admin_secret_arn" {
  description = "ARN of the Grafana admin credential secret, granted to the External Secrets Operator role"
  value       = aws_secretsmanager_secret.grafana_admin.arn
}

output "grafana_admin_secret_name" {
  description = "Name of the Grafana admin credential secret, used as the ExternalSecret remote key"
  value       = aws_secretsmanager_secret.grafana_admin.name
}
