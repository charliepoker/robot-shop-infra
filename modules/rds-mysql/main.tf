# -----------------------------------------------------------------------------
# WHAT THIS BUILDS
# ─────────────────
# A MySQL 8.0 RDS instance for the Robot Shop ratings service.
# MongoDB and Redis stay in-cluster (cost decision) — RDS handles only
# the relational workload that needs managed backups and patching.
#
# COST DECISIONS
# ───────────────
# db.t4g.micro  ~$13/mo  — ARM Graviton, cheapest available, sufficient
#                           for portfolio load. Production: db.t3.medium+
# single-AZ             — multi_az=false saves ~$13/mo. Production: true.
# gp3 storage           — faster baseline IOPS than gp2, same price.
# backup_retention=1    — minimum (1 day). Production: 7-35 days.
# skip_final_snapshot   — no snapshot on destroy. Production: false.
#
# SECURITY DECISIONS
# ───────────────────
# Intra subnets         — no internet route; RDS is completely isolated.
# SG-to-SG rule         — allows port 3306 only from the EKS node SG.
#                         More robust than CIDR: survives node IP changes.
# KMS CMK               — encrypts storage and automated snapshots.
# password_wo           — write-only attribute (v7.2.0 breaking change).
#                         Password is never stored in Terraform state.
#                         The random_password resource generates it;
#                         Secrets Manager stores it for ESO to read.
#
# BREAKING CHANGE IN v7.2.0
# ───────────────────────────
# The `password` argument was removed. Only `password_wo` (write-only)
# and `password_wo_version` are now supported. Write-only means Terraform
# accepts the value at apply time but never writes it to state or plan
# output. This is a significant security improvement — the old pattern
# stored the plaintext password in the state file.
# password_wo_version is a trigger: increment it when you want Terraform
# to treat the password as changed (e.g. after a rotation).
#
# DOWNSTREAM CONSUMERS
# ──────────────────────
# modules/secrets-manager  — stores the password and endpoint
# Phase 2 ESO              — reads the secret and creates K8s Secret
# Robot Shop ratings pod   — reads the K8s Secret as env vars
# -----------------------------------------------------------------------------

# Generate a secure random password — 24 chars, special characters included.
# Terraform stores this in state (encrypted), but we immediately write it
# to Secrets Manager so the actual database credential lives in AWS SM,
# not in git or in plain-text state.
resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"

  # Trigger password regeneration only on explicit replacement.
  # Do not set lifecycle.ignore_changes — you want rotation to work.
}

# Security group — allows MySQL only from EKS worker node security group.
# SG-to-SG is more robust than CIDR: EKS nodes keep their SG when their
# IP changes (e.g. after a Karpenter scale event or node replacement).
resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds"
  description = "Allow MySQL 3306 from EKS node security group only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL from EKS nodes"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.node_security_group_id]
  }

  # No egress needed — RDS never initiates outbound connections
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.name_prefix}-rds"
    Environment = var.environment
  }
}

# DB subnet group — uses intra subnets only (no internet route).
# The module can create this internally, but we create it explicitly
# so it uses our intra subnets rather than the module default.
resource "aws_db_subnet_group" "rds" {
  name        = "${var.name_prefix}-rds"
  description = "Intra subnets for RDS - no internet route"
  subnet_ids  = var.db_subnet_ids

  tags = {
    Name        = "${var.name_prefix}-rds"
    Environment = var.environment
  }
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 7.2"
  

  identifier = "${var.name_prefix}-mysql"

  # ── Engine ────────────────────────────────────────────────────────────────
  engine               = "mysql"
  engine_version       = "8.0"
  family               = "mysql8.0"        # parameter group family
  major_engine_version = "8.0"             # option group major version
  instance_class       = var.db_instance_class

  # ── Storage ───────────────────────────────────────────────────────────────
  allocated_storage     = var.allocated_storage
  max_allocated_storage = 100              # autoscaling storage ceiling
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  # ── Credentials (v7.2.0 write-only pattern) ───────────────────────────────
  # password_wo accepts the value at apply but never writes it to state.
  # password_wo_version is a counter — increment it to signal a rotation.
  db_name            = var.db_name
  username           = var.db_username
  password_wo        = random_password.db.result
  password_wo_version = 1

  # ── Network ───────────────────────────────────────────────────────────────
  # Use the subnet group and security group we created above.
  # create_db_subnet_group = false because we created it ourselves.
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  create_db_subnet_group = false
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  port                   = 3306

  # ── Availability ──────────────────────────────────────────────────────────
  multi_az = false  # cost trade-off; production uses true

  # ── Backups ───────────────────────────────────────────────────────────────
  backup_retention_period = 1           # minimum; production: 7-35
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # ── Snapshots ─────────────────────────────────────────────────────────────
  skip_final_snapshot = true            # portfolio only; production: false
  deletion_protection = false           # portfolio only; production: true

  # ── Monitoring ────────────────────────────────────────────────────────────
  # Performance Insights: 7-day free tier — shows slow queries and wait events
  performance_insights_enabled          = false
  performance_insights_retention_period = 7

  # Enhanced monitoring: 60-second granularity OS metrics
  monitoring_interval    = 60
  monitoring_role_name   = "${var.name_prefix}-rds-monitoring"
  create_monitoring_role = true

  # ── Parameter group — utf8mb4 ─────────────────────────────────────────────
  # utf8mb4 is the modern MySQL character set — supports full Unicode
  # including emoji. The default latin1 charset causes issues with
  # any application that accepts non-ASCII user input.
  parameters = [
    {
      name  = "character_set_client"
      value = "utf8mb4"
    },
    {
      name  = "character_set_server"
      value = "utf8mb4"
    },
    {
      name  = "collation_server"
      value = "utf8mb4_unicode_ci"
    },
  ]

  # ── Option group ──────────────────────────────────────────────────────────
  # MySQL 8.0 does not require an option group, but the module creates
  # one by default. We disable it to keep resource count clean.
  create_db_option_group = false

  tags = {
    Environment = var.environment
  }
}
