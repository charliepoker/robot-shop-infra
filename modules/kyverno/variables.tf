variable "cluster_name" {
  description = "EKS cluster name (Pod Identity association + IAM naming)"
  type        = string
}
variable "namespace" {
  description = "Namespace Kyverno runs in"
  type        = string
  default     = "kyverno"
}
variable "service_account" {
  description = "Kyverno admission-controller SA (the one that runs verifyImages)"
  type        = string
  default     = "kyverno-admission-controller"
}
variable "tags" {
  type    = map(string)
  default = {}
}
