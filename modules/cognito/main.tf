###############################################################################
# Cognito user pool for ALB authentication
#
# Puts a login in front of UIs that have none of their own (Prometheus). The ALB
# runs the OAuth2 authorization-code flow against this pool BEFORE a request
# ever reaches a pod, so unauthenticated traffic never touches the cluster.
#
# Design choices:
#   - Admin-created users only. There is no self sign-up, so the pool is a
#     closed allow-list, not a public registration page.
#   - MFA is required (TOTP authenticator app). TOTP is free; SMS MFA costs
#     money and is the weaker factor.
#   - ESSENTIALS tier: the first 10,000 monthly active users are free. This
#     pool will have one.
#   - Lives outside the cluster lifecycle. `make destroy-targeted` does not
#     touch it, so the cluster rebuild drill (Phase 7/8) does not change the
#     pool ARN, client ID or domain that the GitOps repo references.
#   - No client secret leaves Terraform. The ALB reads it from Cognito itself
#     (cognito-idp:DescribeUserPoolClient), so nothing sensitive is written to
#     the GitOps repo or to a Kubernetes Secret.
#
# User accounts are data, not infrastructure. They are created with the CLI
# (see the Phase 5 runbook), which also keeps personal email addresses out of
# this public repository.
###############################################################################

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Domain prefix
#
# The hosted sign-in page lives at <prefix>.auth.<region>.amazoncognito.com and
# the prefix must be globally unique. Hex output (0-9a-f) can never spell the
# words Cognito forbids in a prefix (aws, amazon, cognito).
# -----------------------------------------------------------------------------

resource "random_id" "domain" {
  byte_length = 4
}

# -----------------------------------------------------------------------------
# User pool
# -----------------------------------------------------------------------------

resource "aws_cognito_user_pool" "this" {
  name           = "${var.name_prefix}-${var.environment}-observability"
  user_pool_tier = "ESSENTIALS"

  # INACTIVE so `terraform destroy` works at teardown. Production would set ACTIVE.
  deletion_protection = "INACTIVE"

  # Sign in with an email address; Cognito verifies it.
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  mfa_configuration = "ON"

  software_token_mfa_configuration {
    enabled = true
  }

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length                   = 14
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-${var.environment}-observability"
    Environment = var.environment
    Component   = "alb-authentication"
    ManagedBy   = "terraform"
  })
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.name_prefix}-auth-${random_id.domain.hex}"
  user_pool_id = aws_cognito_user_pool.this.id
}

# -----------------------------------------------------------------------------
# App client used by the ALB
#
# The ALB requires: a client secret, the authorization-code flow, the openid
# scope, and a callback of exactly https://<host>/oauth2/idpresponse.
# -----------------------------------------------------------------------------

resource "aws_cognito_user_pool_client" "alb" {
  name         = "${var.name_prefix}-${var.environment}-alb"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = true

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid"]
  supported_identity_providers         = ["COGNITO"]

  callback_urls = [for host in var.protected_hostnames : "https://${host}/oauth2/idpresponse"]

  # Do not reveal whether an email address has an account.
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 1

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}
