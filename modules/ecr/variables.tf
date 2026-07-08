variable "repo_names" {
  description = "List of ECR repository names — one per Robot Shop microservice"
  type        = list(string)
}

variable "environment" {
  description = "Environment label used in tags"
  type        = string
}

variable "image_tag_mutability" {
  description = <<-EOT
    IMMUTABLE: once pushed, a tag cannot be overwritten.
    This is critical for traceability — you can always trace a running
    container back to the exact git commit that produced it.
    MUTABLE would allow someone to silently overwrite :latest, making
    rollbacks and incident investigations unreliable.
  EOT
  type        = string
  default     = "IMMUTABLE"
}

variable "tagged_images_to_keep" {
  description = "Number of tagged images to retain per repository before expiring older ones"
  type        = number
  default     = 10
}

variable "untagged_expiry_days" {
  description = <<-EOT
    Days before untagged images are deleted.
    Untagged images are layer blobs left behind by multi-stage builds
    and failed pushes. Without this rule, they accumulate indefinitely
    and inflate your ECR storage bill.
  EOT
  type        = number
  default     = 7
}
