# modules/aws-lb-controller/variables.tf

variable "cluster_name" {
  description = "EKS cluster name (must match the running cluster, used for Pod Identity association and IAM role/policy naming)"
  type        = string
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}
