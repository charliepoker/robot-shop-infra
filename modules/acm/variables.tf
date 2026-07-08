variable "domain_name" {
  description = "Root domain name (e.g. devopsportfolio.com)"
  type        = string
}

variable "zone_id" {
  description = <<-EOT
    Route53 hosted zone ID.
    ACM uses this to create the DNS validation CNAME records automatically.
    Comes from module.route53.zone_id — your hosted zone must exist and
    your registrar must be pointing at the AWS nameservers before this
    certificate can be validated.
  EOT
  type        = string
}

variable "environment" {
  description = "Environment label used in tags"
  type        = string
}
