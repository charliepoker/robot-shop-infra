data "aws_vpc" "selected" {
  id = var.vpc_id
}
# The master password is managed by RDS itself (manage_master_user_password
# below), not by Terraform. RDS generates it inside AWS and writes it to an
# AWS-managed Secrets Manager secret at instance-creation time. The instance and
# the secret are therefore set by a single atomic AWS operation and cannot
# drift. Terraform never sees or stores the master password, and there is no
# random_password resource to regenerate out of step with the instance.

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
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
    description = "Allow all egress within VPC"
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
  family               = "mysql8.0" # parameter group family
  major_engine_version = "8.0"      # option group major version
  instance_class       = var.db_instance_class

  # ── Storage ───────────────────────────────────────────────────────────────
  allocated_storage     = var.allocated_storage
  max_allocated_storage = 100 # autoscaling storage ceiling
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  # ── Credentials (RDS-managed master password) ─────────────────────────────
  # RDS generates and owns the master password and stores it in an AWS-managed
  # secret. This makes instance/secret drift structurally impossible: there is
  # no separate random_password to fall out of sync, and no password_wo_version
  # counter to forget to bump.
  #
  # No master_user_secret_kms_key_id: the managed secret is encrypted with the
  # AWS-owned default aws/secretsmanager key, not our CMK. That key cannot be
  # changed on an existing instance (AWS rejects it on ModifyDBInstance), and
  # it doesn't matter for us anyway — ESO never reads this managed secret. It
  # only reads the mirrored robot-shop/rds-credentials secret below, which
  # modules/secrets-manager encrypts with our CMK explicitly.
  db_name                     = var.db_name
  username                    = var.db_username
  manage_master_user_password = true


  # ── Network ───────────────────────────────────────────────────────────────
  # Use the subnet group and security group we created above.
  # create_db_subnet_group = false because we created it ourselves.
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  create_db_subnet_group = false
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  port                   = 3306

  # ── Availability ──────────────────────────────────────────────────────────
  multi_az = false # cost trade-off; production uses true

  # ── Backups ───────────────────────────────────────────────────────────────
  backup_retention_period = 1 # minimum; production: 7-35
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # ── Snapshots ─────────────────────────────────────────────────────────────
  skip_final_snapshot = true  # portfolio only; production: false
  deletion_protection = false # portfolio only; production: true

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

# Read the RDS-managed master secret so the module can expose the actual
# username and password to modules/secrets-manager for mirroring into the
# stable-named robot-shop/rds-credentials secret that ESO consumes.
#
# The managed secret's value is a JSON document: {"username":..,"password":..}.
# This data source depends on the managed secret's ARN, so Terraform reads it
# only after RDS has created and populated it.
#
# NOTE: the password does transit Terraform state via this data source. That is
# the same exposure the previous random_password approach had, and no worse. If
# you later require the password to never touch state, switch ESO to read the
# managed secret directly (see runbook) and delete this data source plus the
# mirror — at the cost of handling the managed secret's dynamic name in gitops.
data "aws_secretsmanager_secret_version" "rds_managed" {
  secret_id = module.rds.db_instance_master_user_secret_arn
}

locals {
  rds_managed_creds = jsondecode(data.aws_secretsmanager_secret_version.rds_managed.secret_string)
}
