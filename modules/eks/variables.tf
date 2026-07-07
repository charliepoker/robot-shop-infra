variable "name_prefix" {
  description = "Used as the EKS cluster name and prefix for all associated resources"
  type        = string
}

variable "environment" {
  description = "Environment label used in tags"
  type        = string
}

variable "cluster_version" {
  description = <<-EOT
    Kubernetes version for the EKS cluster.
    Must be a version currently in EKS standard support.
    Standard support versions as of July 2026: 1.33, 1.34, 1.35, 1.36
    Using 1.35 — released Jan 27 2026, well-tested, full addon compatibility,
    avoids bleeding-edge risk of 1.36 (released June 2 2026, only 5 weeks old).
  EOT
  type        = string
  default     = "1.35"
}

variable "vpc_id" {
  description = "VPC ID from modules/vpc — the cluster control plane ENIs are placed here"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs from modules/vpc — nodes run here, never in public subnets"
  type        = list(string)
}

variable "ebs_kms_key_arn" {
  description = "KMS CMK ARN from modules/kms — used to encrypt node root EBS volumes"
  type        = string
}

variable "node_instance_type" {
  description = <<-EOT
    EC2 instance type for the baseline managed node group.
    t3.medium: 2 vCPU, 4 GB RAM — minimum comfortable size for system pods
    (CoreDNS, kube-proxy, vpc-cni, ebs-csi, pod-identity-agent) plus a few
    app pods. Karpenter handles burst capacity in Phase 2.
  EOT
  type        = string
  default     = "t3.medium"
}

variable "node_min_size" {
  description = "Minimum nodes — must be >=2 to tolerate a single node failure"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum nodes the managed node group can scale to"
  type        = number
  default     = 5
}

variable "node_desired_size" {
  description = "Node count at cluster creation time"
  type        = number
  default     = 2
}
