variable "name_prefix" {
  description = "Prefix applied to the VPC name and all subnet names (e.g. robot-shop)"
  type        = string
}

variable "environment" {
  description = "Environment label used in tags"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. /16 gives 65,536 addresses across all subnets."
  type        = string
  default     = "10.0.0.0/16"
}

variable "cluster_name" {
  description = <<-EOT
    EKS cluster name used in subnet tags.
    EKS requires two specific tags on subnets before the AWS Load Balancer
    Controller can place ALBs into them:
      Public  → kubernetes.io/role/elb = 1
      Private → kubernetes.io/role/internal-elb = 1
    Karpenter also uses the cluster name tag to discover which subnets
    it is allowed to launch replacement nodes into.
  EOT
  type        = string
}
