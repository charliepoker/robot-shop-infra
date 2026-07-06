terraform {
  required_version = ">= 1.11"

  backend "s3" {
    bucket       = "robotshop-tf-state-448049792905"
    key          = "prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile  = true
  }
}