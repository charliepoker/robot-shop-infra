output "db_endpoint" {
  description = <<-EOT
    RDS hostname (without port).
    Passed to modules/secrets-manager as db_host.
    Written into the JSON secret that ESO syncs to a K8s Secret.
  EOT
  value       = module.rds.db_instance_address
}

output "db_port" {
  description = "RDS port (3306) — written into the JSON secret"
  value       = module.rds.db_instance_port
}

output "db_name" {
  description = "Database name inside the instance"
  value       = module.rds.db_instance_name
}

output "db_instance_id" {
  description = "RDS instance identifier — use in aws rds describe-db-instances"
  value       = module.rds.db_instance_identifier
}

output "db_instance_arn" {
  description = "RDS instance ARN"
  value       = module.rds.db_instance_arn
}

output "db_password" {
  description = <<-EOT
    Generated master password — passed to modules/secrets-manager.
    Marked sensitive so it never appears in terraform plan or apply output.
    Note: because password_wo is write-only, the password is not stored
    in RDS state. This output comes from random_password, which IS in state
    (encrypted). The modules/secrets-manager module writes it to AWS SM.
  EOT
  value       = random_password.db.result
  sensitive   = true
}

output "security_group_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
}

output "db_subnet_group_name" {
  description = "DB subnet group name"
  value       = aws_db_subnet_group.rds.name
}
