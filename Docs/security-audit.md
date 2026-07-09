# Security Audit — Accepted Risks

## AWS-0040 / AWS-0041 — EKS Public Endpoint
**Finding:** EKS cluster has a public API endpoint accessible from 0.0.0.0/0
**Accepted:** Yes
**Justification:** Portfolio project with no bastion host or VPN. Public endpoint
is required for local kubectl access. In production this would be restricted to
office CIDR ranges or disabled entirely with a bastion/VPN.
**Mitigating controls:** Private endpoint also enabled; access entries restrict
who can authenticate to the cluster regardless of network access.

## AWS-0104 — Unrestricted Security Group Egress (EKS nodes)
**Finding:** EKS node security group allows all outbound traffic
**Accepted:** Yes
**Justification:** EKS nodes need egress to pull images from ECR (via VPC
endpoints), reach the API server, and send metrics. Restricting egress further
requires enumerating every service endpoint — not practical and not standard.
The VPC endpoints and private subnets provide the real isolation boundary.

---

## Checkov findings (checkov -d environments/prod --framework terraform)

Passed: 100 | Failed: 25 | Skipped: 0

### CKV_AWS_136 — ECR repositories not encrypted with KMS CMK (11 findings)
**Classification:** Accepted Risk
**Justification:** Same as tfsec aws-ecr-repository-customer-key above.
AES256 encryption is sufficient for portfolio use. KMS CMK adds per-API-call
charges across 11 repos with frequent CI builds.
**Production remediation:** Set encryption_type = "KMS" with a dedicated ECR CMK.

### CKV_TF_1 — Module sources not pinned to commit hash (4 findings)
**Classification:** Accepted Risk
**Justification:** Using Terraform registry pattern with version constraints
and .terraform.lock.hcl provides equivalent supply chain guarantees.
The lockfile pins exact version and SHA256 hash on terraform init.
Switching to git commit-hash sourcing would lose semantic version constraints
and break the standard Terraform module registry workflow.
**Affected modules:** eks, karpenter, rds, vpc, vpc_endpoints

### CKV_AWS_111 / CKV_AWS_356 / CKV_AWS_109 — KMS key policy uses kms:* on * resource (9 findings)
**Classification:** False Positive
**Justification:** The flagged statement is the mandatory root account statement
required by AWS in every KMS key policy. Without it, the key becomes permanently
inaccessible and unrecoverable. The resource = ["*"] in a key policy context
means "this key" — not all KMS keys in the account. This is required AWS
documentation pattern, not a misconfiguration.
Reference: https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-default.html