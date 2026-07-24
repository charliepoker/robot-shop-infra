###############################################################################
# Per service MySQL credentials
#
# Phase 3 Task 2. Creates one Secrets Manager secret per application that talks
# to RDS MySQL, each with its own generated password and least privilege user.
#
# The RDS master credential in robot-shop/rds-credentials is deliberately left
# alone. Nothing in the robot-shop namespace is ever allowed to read it.
#
# This file is self contained: variables, resources and outputs all live here so
# it can be dropped into modules/secrets-manager/ without touching any existing
# file in the module.
###############################################################################

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}

variable "app_db_mysql_host" {
  description = "RDS MySQL endpoint address with no port suffix"
  type        = string
}

variable "app_db_mysql_port" {
  description = "Port the RDS MySQL instance listens on"
  type        = number
  default     = 3306
}

variable "app_db_credentials" {
  description = "Map of application name to the MySQL database and username it should own"

  type = map(object({
    database = string
    username = string
  }))

  default = {}

  validation {
    condition     = alltrue([for k, v in var.app_db_credentials : can(regex("^[a-z][a-z0-9_]{0,30}$", v.username))])
    error_message = "Each username must be lowercase alphanumeric with underscores and at most 31 characters, the MySQL 8.0 limit."
  }
}

variable "app_db_secret_recovery_window_days" {
  description = "Days before a deleted secret is permanently removed. Zero permits immediate reuse of the name during rebuild cycles"
  type        = number
  default     = 0

  validation {
    condition     = var.app_db_secret_recovery_window_days == 0 || (var.app_db_secret_recovery_window_days >= 7 && var.app_db_secret_recovery_window_days <= 30)
    error_message = "Recovery window must be 0 or between 7 and 30 days."
  }
}

# -----------------------------------------------------------------------------
# Generated passwords
#
# override_special deliberately excludes the characters that break either the
# PDO DSN parser, a JDBC URL, or a shell heredoc in the bootstrap job:
#   / @ " ' \ ` ; , : space
# -----------------------------------------------------------------------------

resource "random_password" "app_db" {
  for_each = var.app_db_credentials

  length           = 32
  special          = true
  min_lower        = 4
  min_upper        = 4
  min_numeric      = 4
  min_special      = 2
  override_special = "!#$%&*()-_=+[]{}<>?."
}

# -----------------------------------------------------------------------------
# Secrets
#
# Descriptions are single line ASCII on purpose. AWS rejects tabs, newlines and
# em dashes in this field, which fails the apply with an unhelpful error.
# -----------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "app_db" {
  for_each = var.app_db_credentials

  name                    = "robot-shop/${each.key}-db"
  description             = "MySQL credentials for the robot-shop ${each.key} service"
  recovery_window_in_days = var.app_db_secret_recovery_window_days

  tags = merge(
    var.tags,
    {
      Name      = "robot-shop/${each.key}-db"
      Service   = each.key
      Component = "database-credentials"
    }
  )
}

resource "aws_secretsmanager_secret_version" "app_db" {
  for_each = var.app_db_credentials

  secret_id = aws_secretsmanager_secret.app_db[each.key].id

  secret_string = jsonencode({
    MYSQL_HOST     = var.app_db_mysql_host
    MYSQL_PORT     = tostring(var.app_db_mysql_port)
    MYSQL_DATABASE = each.value.database
    MYSQL_USERNAME = each.value.username
    MYSQL_PASSWORD = random_password.app_db[each.key].result
  })

  # Terraform seeds the initial credential and then stops managing its value.
  #
  # Without this, the Phase 7 secret rotation scenario is self defeating: you
  # rotate the password out of band, and the next terraform apply quietly
  # reverts Secrets Manager to the value in state while the live MySQL user
  # keeps the new one. The services then fail to authenticate for reasons that
  # look nothing like the cause.
  #
  # To deliberately re run a password, taint the random_password resource:
  #   terraform taint 'module.secrets_manager.random_password.app_db["ratings"]'
  lifecycle {
    ignore_changes = [secret_string]
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "app_db_secret_arns" {
  description = "Map of application name to the ARN of its MySQL credential secret"
  value       = { for k, v in aws_secretsmanager_secret.app_db : k => v.arn }
}

output "app_db_secret_names" {
  description = "Map of application name to the name of its MySQL credential secret"
  value       = { for k, v in aws_secretsmanager_secret.app_db : k => v.name }
}

output "app_db_secret_prefix_arn" {
  description = "Wildcard ARN covering every robot-shop secret, for scoping the External Secrets Operator IAM policy"
  value       = "arn:aws:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:robot-shop/*"
}

# These two are almost certainly already declared elsewhere in the module. If
# terraform init reports a duplicate data source, delete the block below rather
# than the one that already exists.
data "aws_region" "current" {}

data "aws_caller_identity" "current" {}
