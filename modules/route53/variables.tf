variable "domain_name" {
  description = "The public domain to create a hosted zone for (e.g. devopsportfolio.com)"
  type        = string
}

variable "environment" {
  description = "Environment label used in tags"
  type        = string
}
