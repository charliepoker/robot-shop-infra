

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  # cidrsubnet("10.0.0.0/16", 8, N) adds 8 bits → /24 blocks
  public_subnets  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i)]       # .0 .1 .2
  private_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 10)]  # .10 .11 .12
  intra_subnets   = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 20)]  # .20 .21 .22
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.6"

  name = var.name_prefix
  cidr = var.vpc_cidr
  azs  = local.azs

  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets
  intra_subnets   = local.intra_subnets

  # ── NAT Gateway ────────────────────────────────────────────────────────────
  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  # ── DNS ────────────────────────────────────────────────────────────────────
  # Required for EKS nodes to resolve AWS service hostnames and for
  # private DNS on interface endpoints to work
  enable_dns_hostnames = true
  enable_dns_support   = true

  # ── Flow Logs ──────────────────────────────────────────────────────────────
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60

  # ── Subnet Tags ────────────────────────────────────────────────────────────
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "karpenter.sh/discovery"                    = var.cluster_name
  }

  intra_subnet_tags = {
    "Purpose" = "database"
  }

  tags = {
    Environment = var.environment
  }
}

# ── Security Group for Interface Endpoints ─────────────────────────────────────
# Interface endpoints are ENIs in your private subnets. They only need to
# accept HTTPS (443) from within the VPC — nothing else should reach them.

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.name_prefix}-vpc-endpoints"
  description = "Allow HTTPS from VPC CIDR to interface endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from within the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.name_prefix}-vpc-endpoints"
    Environment = var.environment
  }
}

# ── VPC Endpoints ───────────────────────────────────────────────────────────


module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.6"

  vpc_id = module.vpc.vpc_id

  # Default security group for interface endpoints (overridable per endpoint)
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  endpoints = {
    s3 = {
      service      = "s3"
      service_type = "Gateway"
      # Attach to all private and intra route tables so both EKS nodes and
      # the RDS subnet can reach S3 without going through NAT
      route_table_ids = flatten([
        module.vpc.private_route_table_ids,
        module.vpc.intra_route_table_ids,
      ])
      tags = { Name = "${var.name_prefix}-s3" }
    }

    # ECR API — handles registry auth and image manifest/metadata requests
    ecr_api = {
      service             = "ecr.api"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}-ecr-api" }
    }

    # ECR DKR — handles the actual image layer transfers (the docker pull data)
    ecr_dkr = {
      service             = "ecr.dkr"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}-ecr-dkr" }
    }

    # STS — Pod Identity and token exchange; every IAM call from a pod
    # goes through STS, so this keeps all credential issuance off the NAT
    sts = {
      service             = "sts"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
      tags                = { Name = "${var.name_prefix}-sts" }
    }
  }

  tags = {
    Environment = var.environment
  }
}
