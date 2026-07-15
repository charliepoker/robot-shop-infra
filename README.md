# robot-shop-infra

[![Terraform Plan](https://github.com/charliepoker/robot-shop-infra/actions/workflows/terraform-plan.yml/badge.svg)](https://github.com/charliepoker/robot-shop-infra/actions/workflows/terraform-plan.yml)
[![Terraform Apply](https://github.com/charliepoker/robot-shop-infra/actions/workflows/terraform-apply.yml/badge.svg)](https://github.com/charliepoker/robot-shop-infra/actions/workflows/terraform-apply.yml)
[![Terraform](https://img.shields.io/badge/terraform-%3E%3D1.11-623CE4?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-provider%20~%3E6.0-FF9900?logo=amazonaws)](https://registry.terraform.io/providers/hashicorp/aws/latest)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Production-grade EKS platform on AWS, provisioned entirely through Terraform. Ten modules deploy an EKS cluster, RDS MySQL, container registries, DNS, TLS, secrets management, and federated CI in a single `terraform apply`.

Runs the [Instana Robot Shop](https://github.com/instana/robot-shop) microservices application. The companion GitOps repository ([robot-shop-gitOps](https://github.com/charliepoker/robot-shop-gitOps)) handles the Kubernetes and application layer.

---

## Architecture

![Robot Shop Infrastructure Architecture](docs/diagrams/robot-shop-infra.svg)

Every AWS resource in this diagram is provisioned by Terraform from an empty repository. No console clicks, no manual bootstrapping other than the S3 state bucket itself.

---

## Stack

| Layer | Technology | Version |
|---|---|---|
| IaC | Terraform | `>= 1.11` |
| Provider | `hashicorp/aws` | `~> 6.0` |
| Network | `terraform-aws-modules/vpc` | `~> 6.6` |
| Compute | `terraform-aws-modules/eks` | `~> 21.0` (v21.24.0) |
| Kubernetes | EKS | 1.35 |
| Autoscaling | Karpenter | v1.13.0 |
| Database | `terraform-aws-modules/rds` | `~> 7.2` (MySQL 8.0) |
| Registry | ECR | 11 microservice repos |
| DNS | Route53 | `devopsportfolio.com` |
| TLS | ACM | `*.devopsportfolio.com` wildcard |
| Secrets | AWS Secrets Manager | JSON-structured |
| Identity | GitHub OIDC | Federated, no static keys |

---

## Repository structure

```
robot-shop-infra/
├── .github/workflows/
│   ├── terraform-plan.yml       # PR: fmt, validate, tflint, trivy, checkov, plan, infracost
│   └── terraform-apply.yml      # Push to main: apply via OIDC, gated on `prod` environment
├── docs/
│   ├── diagrams/
│   │   └── robot-shop-infra.svg
│   └── security-audit.md        # tfsec + checkov triage: fixed / false positive / accepted risk
├── environments/prod/
│   ├── backend.tf               # S3 native state locking (no DynamoDB)
│   ├── providers.tf             # AWS provider + default tags
│   ├── versions.tf              # Terraform + provider constraints
│   ├── variables.tf             # Environment inputs
│   ├── main.tf                  # Wires all modules
│   └── outputs.tf               # Cluster endpoints, ARNs, IDs
├── modules/
│   ├── kms/                     # 3 CMKs: rds, ebs, s3 — rotation enabled
│   ├── route53/                 # Public hosted zone
│   ├── vpc/                     # 3-AZ, single NAT, VPC endpoints
│   ├── eks/                     # EKS 1.35 + EBS CSI via Pod Identity
│   ├── karpenter/               # IAM + SQS + EventBridge (Helm chart in gitOps repo)
│   ├── rds-mysql/               # db.t4g.micro, gp3, encrypted, intra subnets
│   ├── ecr/                     # 11 repos, immutable tags, lifecycle policy
│   ├── acm/                     # Wildcard cert, DNS-validated
│   ├── secrets-manager/         # RDS credentials as JSON
│   └── github-oidc/             # OIDC provider + IAM role for CI
├── .pre-commit-config.yaml      # fmt, validate, tflint, trivy hooks
├── .tflint.hcl                  # AWS ruleset config
├── .trivyignore                 # Documented accepted risks
└── Makefile                     # make fmt / plan / apply / destroy
```

---

## Key architectural decisions

Every decision is a deliberate trade-off between cost, complexity, and production-readiness. Production remediation for the cost-driven trade-offs is documented in [`docs/security-audit.md`](docs/security-audit.md).

| Decision | Rationale |
|---|---|
| **Single NAT gateway** | Saves ~$64/month vs one-per-AZ. Trade-off: if us-east-1a NAT fails, other AZs lose egress. Production: `one_nat_gateway_per_az = true`. |
| **S3 native state locking** | `use_lockfile = true` (Terraform ≥1.11) replaces the deprecated DynamoDB pattern. One less resource. |
| **EKS Pod Identity, not IRSA** | v21 module default. Simpler than IRSA — no service account annotation dance. Both coexist. |
| **Access entries, not aws-auth** | The aws-auth ConfigMap approach is deprecated. Access entries are a proper AWS API resource. |
| **RDS in intra subnets** | No internet route at all. Even a misconfigured security group cannot expose the database. |
| **SG-to-SG rules, not CIDR** | RDS SG allows 3306 from the EKS node SG. Survives node IP changes without policy updates. |
| **db.t4g.micro (single-AZ)** | ~$13/month. Sufficient for a Robot Shop ratings service. Production: db.t3.medium+ with multi-AZ. |
| **MongoDB & Redis in-cluster** | Managed alternatives (DocumentDB, ElastiCache) add ~$30-50/month with no operational benefit here. |
| **KMS CMKs for RDS/EBS/S3** | Customer-managed keys give per-operation CloudTrail auditing and key policy control. AWS-managed keys don't. |
| **ECR immutable tags** | A tag maps to exactly one image digest forever. No silent `:latest` overwrites. |
| **Wildcard ACM cert** | One cert covers `shop.`, `argocd.`, `grafana.`, `prometheus.` etc. DNS-validated for automatic renewal. |
| **GitHub OIDC federation** | Zero static AWS credentials in GitHub secrets. Trust policy scoped to repo + environment. |
| **`password_wo` write-only for RDS** | v7.2.0 pattern. Password is never written to Terraform state. Retrieved via random_password → Secrets Manager. |

---

## CI/CD pipeline

Two GitHub Actions workflows enforce quality on every change.

### `terraform-plan.yml` — runs on every PR
- **Pre-commit hooks** — `terraform fmt`, `terraform validate`, `tflint` (AWS ruleset)
- **Security scan** — `trivy` on Terraform code, `checkov` at HIGH/CRITICAL threshold
- **Terraform plan** — output posted as PR comment
- **Cost estimate** — `infracost` breakdown posted as PR comment

### `terraform-apply.yml` — runs on merge to `main`
- **OIDC authentication** — `aws-actions/configure-aws-credentials@v4`
- **Environment gate** — `prod` environment requires manual approval
- **Concurrency lock** — prevents parallel applies against the same state
- **Terraform apply** — auto-approved after all PR checks pass

Both workflows use GitHub OIDC federation. No long-lived AWS credentials are stored in GitHub.

---

## Getting started

### Prerequisites

- AWS account with admin credentials (for initial bootstrap only)
- `aws-cli` >= 2.15
- `terraform` >= 1.11
- `kubectl` >= 1.35
- `pre-commit` >= 3.5 (for local hooks)
- A domain name — registrar configured to point at Route53 nameservers

### One-time bootstrap

```bash
# 1. Create the S3 bucket for Terraform state
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="robotshop-tf-state-${ACCOUNT_ID}"

aws s3api create-bucket --bucket "$BUCKET" --region us-east-1
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# 2. Update backend.tf with your account ID
sed -i '' "s/<YOUR_ACCOUNT_ID>/$ACCOUNT_ID/" environments/prod/backend.tf

# 3. Install pre-commit hooks
pre-commit install
tflint --init --config=.tflint.hcl
```

### Deploy

```bash
cd environments/prod
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Configure kubectl
aws eks update-kubeconfig --name robot-shop --region us-east-1
kubectl get nodes -o wide

# Copy the nameservers to your registrar (one-time)
terraform output route53_name_servers
```

Full apply takes ~20 minutes. EKS control plane creation is the slow step.

---

## Teardown

The Makefile provides two destroy modes.

**Full destroy:**
```bash
make destroy
```

**Targeted destroy — preserves Route53, ACM, and GitHub OIDC:**
```bash
terraform destroy \
  -target=module.eks \
  -target=module.karpenter \
  -target=module.rds \
  -target=module.ecr \
  -target=module.secrets_manager \
  -target=module.vpc \
  -target=module.kms \
  -auto-approve
```

Use the targeted version between work sessions. It keeps the wildcard cert, DNS zone, and OIDC federation intact so the next `terraform apply` is friction-free — no nameserver update, no cert re-validation, no GitHub secret update.

---

## Security posture

Every finding from `tfsec`, `checkov`, and `trivy` has been triaged and documented in [`docs/security-audit.md`](docs/security-audit.md). Each finding is classified as:

- **Fixed** — code was updated to resolve the finding
- **False positive** — tool limitation (usually variable resolution during static analysis)
- **Accepted risk** — deliberate trade-off with production remediation noted

| Tool | Findings | Fixed | False positive | Accepted risk |
|---|---|---|---|---|
| tfsec | 30 | 1 | 12 | 17 |
| checkov | 25 | 0 | 9 | 16 |
| trivy | 0 | — | — | — |

---

## Cost

Estimated monthly cost with all resources running:

| Component | Cost |
|---|---|
| EKS control plane | $73 |
| EKS worker nodes (2× t3.medium) | ~$60 |
| NAT gateway (single) | ~$32 + data |
| RDS db.t4g.micro | ~$13 |
| VPC interface endpoints (3× ECR/STS) | ~$22 |
| EBS storage (100GB gp3) | ~$8 |
| Route53 hosted zone | $0.50 |
| Everything else (S3, KMS, ECR storage, Secrets, ACM) | ~$5 |
| **Total** | **~$213/month** |

Costs drop by ~$130 when using the targeted destroy between sessions.



## License

MIT — see [`LICENSE`](LICENSE).
