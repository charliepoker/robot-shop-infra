resource "aws_acm_certificate" "wildcard" {
  domain_name = "*.${var.domain_name}"

  # SAN for the apex domain — covers devopsportfolio.com in addition
  # to *.devopsportfolio.com. Wildcard certs don't cover the apex by default.
  subject_alternative_names = [var.domain_name]

  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
  Name        = "wildcard-${var.domain_name}"
  Environment = var.environment
}
}

# Create the DNS validation CNAME records in Route53.
# for_each over domain_validation_options handles both the wildcard and
# apex domain entries — one CNAME per unique domain validation requirement.
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.wildcard.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = var.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

# Block until ACM confirms the certificate is ISSUED.
# Terraform apply will wait here — typically 30 seconds to 2 minutes.
resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn = aws_acm_certificate.wildcard.arn

  validation_record_fqdns = [
    for record in aws_route53_record.cert_validation : record.fqdn
  ]
}
