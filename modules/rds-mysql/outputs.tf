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
    Master password, read from the RDS-managed secret. Passed to
    modules/secrets-manager for mirroring into robot-shop/rds-credentials.
    Sourced from the AWS-managed secret (which RDS keeps identical to the
    instance), so it cannot drift from what the instance actually accepts.
  EOT
  value       = local.rds_managed_creds.password
  sensitive   = true
}

output "db_username" {
  description = "Master username, read from the RDS-managed secret."
  value       = local.rds_managed_creds.username
  sensitive   = true
}

output "master_user_secret_arn" {
  description = <<-EOT
    ARN of the AWS-managed master secret RDS created. Kept as an output so you
    can switch ESO to read it directly later, or reference it in a rotation
    schedule. Its name is dynamic (rds!db-<id>), which is why the durable
    gitops path mirrors into the stable robot-shop/rds-credentials instead.
  EOT
  value       = module.rds.db_instance_master_user_secret_arn
}

output "security_group_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
}

output "db_subnet_group_name" {
  description = "DB subnet group name"
  value       = aws_db_subnet_group.rds.name
}
