variable "name_prefix" {
  description = "Prefix for the secret name path (e.g. robot-shop)"
  type        = string
}

variable "environment" {
  description = "Environment label used in tags"
  type        = string
}

variable "db_host" {
  description = "RDS endpoint hostname — from module.rds.db_endpoint"
  type        = string
}

variable "db_port" {
  description = "RDS port — from module.rds.db_port"
  type        = number
}

variable "db_name" {
  description = "Database name inside the RDS instance"
  type        = string
}

variable "db_username" {
  description = "RDS master username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "RDS master password — from module.rds.db_password (random_password output)"
  type        = string
  sensitive   = true
}

variable "recovery_window_in_days" {
  description = <<-EOT
    Days AWS holds a deleted secret before permanent destruction.
    Set to 0 for portfolio use so terraform destroy doesn't leave
    a ghost secret blocking re-creation on the next apply.
    Production would use 7-30 days for accidental deletion protection.
  EOT
  type        = number
  default     = 0
}
