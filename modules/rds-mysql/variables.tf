variable "name_prefix" {
  description = "Prefix for all resource names (e.g. robot-shop)"
  type        = string
}

variable "environment" {
  description = "Environment label used in tags"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID — the RDS security group is created here"
  type        = string
}

variable "db_subnet_ids" {
  description = <<-EOT
    Intra subnet IDs for the RDS subnet group.
    Intra subnets have no internet route at all — not even through NAT.
    This means even a misconfigured security group cannot expose the database.
    These come from module.vpc.intra_subnet_ids.
  EOT
  type        = list(string)
}

variable "node_security_group_id" {
  description = <<-EOT
    Security group ID attached to EKS worker nodes.
    The RDS security group allows port 3306 inbound from this SG only.
    Using SG-to-SG rules instead of CIDR blocks is more secure — if a node
    is replaced, its IP changes but it keeps the same security group.
    Comes from module.eks.node_security_group_id.
  EOT
  type        = string
}

variable "kms_key_arn" {
  description = "KMS CMK ARN for encrypting the RDS instance and its automated snapshots"
  type        = string
}

variable "db_name" {
  description = "Name of the MySQL database to create inside the instance"
  type        = string
  default     = "robotshop"
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_instance_class" {
  description = <<-EOT
    RDS instance class.
    db.t4g.micro: 2 vCPU, 1 GB RAM, ARM Graviton — cheapest option (~$13/mo).
    Sufficient for a portfolio project with light query load.
    Production would use db.t3.medium or larger.
  EOT
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial storage in GB — gp3 minimum is 20 GB"
  type        = number
  default     = 20
}
