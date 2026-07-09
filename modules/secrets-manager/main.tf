resource "aws_secretsmanager_secret" "rds" {
  name                    = "${var.name_prefix}/rds-credentials"
  description             = "RDS MySQL credentials for the Robot Shop ratings service"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id

  # jsonencode produces valid JSON and handles escaping automatically.
  # All values are strings — MYSQL_PORT is cast to string because
  # ESO injects these as environment variable values, which are always strings.
  secret_string = jsonencode({
    MYSQL_HOST     = var.db_host
    MYSQL_PORT     = tostring(var.db_port)
    MYSQL_DATABASE = var.db_name
    MYSQL_USERNAME = var.db_username
    MYSQL_PASSWORD = var.db_password
  })
}
