# modules/cert-manager/variables.tf

variable "cluster_name" {
  description = "EKS cluster name (used for Pod Identity association and IAM naming)"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route53 public hosted zone ID (e.g. module.route53.zone_id). DNS-01 record writes are scoped to this zone."
  type        = string
}

variable "domain_name" {
  description = "Domain cert-manager issues certs for, used for policy description/tagging (e.g. devopsportfolio.com)"
  type        = string
}

variable "namespace" {
  description = "Namespace cert-manager runs in (must match the Argo CD Application destination namespace)"
  type        = string
  default     = "cert-manager"
}

variable "service_account" {
  description = "cert-manager controller ServiceAccount name (must match the Helm chart's serviceAccount.name)"
  type        = string
  default     = "cert-manager"
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}
