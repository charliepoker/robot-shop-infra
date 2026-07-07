provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "robot-shop"
      Environment = var.environment
      ManagedBy   = "terraform"
      Repo        = "robot-shop-infra"
    }
  }
}
