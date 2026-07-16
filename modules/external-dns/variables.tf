# modules/external-dns/variables.tf

variable "cluster_name" {
  description = "EKS cluster name (used for Pod Identity association and IAM naming)"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route53 public hosted zone ID for the domain (e.g. from module.route53.zone_id). ChangeResourceRecordSets is scoped to this zone only."
  type        = string
}

variable "domain_name" {
  description = "Domain managed by ExternalDNS, used only for the policy description/tagging (e.g. devopsportfolio.com)"
  type        = string
}

variable "namespace" {
  description = "Namespace ExternalDNS runs in (must match the Argo CD Application's destination namespace)"
  type        = string
  default     = "external-dns"
}

variable "service_account" {
  description = "ServiceAccount name ExternalDNS uses (must match the Helm chart's serviceAccount.name)"
  type        = string
  default     = "external-dns"
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}
