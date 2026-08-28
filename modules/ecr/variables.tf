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
    IMMUTABLE_WITH_EXCLUSION: real image tags stay immutable (a running
    container always maps to the exact commit that built it), EXCEPT tags
    matching mutable_tag_exclusions. Cosign writes signature/attestation tags
    as `sha256-<digest>.sig` / `.att`; these are content-addressed and must be
    overwritable when the same image is re-signed. Excluding `sha256-*` keeps
    image tags immutable while letting cosign re-attach cleanly.
    Requires AWS provider >= 6.8.0.
    Valid: MUTABLE, IMMUTABLE, IMMUTABLE_WITH_EXCLUSION, MUTABLE_WITH_EXCLUSION.
  EOT
  type        = string
  default     = "IMMUTABLE_WITH_EXCLUSION"
}

variable "mutable_tag_exclusions" {
  description = "Tag wildcard patterns kept mutable under *_WITH_EXCLUSION (cosign sig/att artifacts)."
  type        = list(string)
  default     = ["sha256-*"]
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
