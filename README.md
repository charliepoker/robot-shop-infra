# robot-shop-infra

[![Terraform Plan](https://github.com/charliepoker/robot-shop-infra/actions/workflows/terraform-plan.yml/badge.svg)](https://github.com/charliepoker/robot-shop-infra/actions/workflows/terraform-plan.yml)
[![Terraform Apply](https://github.com/charliepoker/robot-shop-infra/actions/workflows/terraform-apply.yml/badge.svg)](https://github.com/charliepoker/robot-shop-infra/actions/workflows/terraform-apply.yml)
[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.11-623CE4?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Provider-orange?logo=amazonaws)](https://registry.terraform.io/providers/hashicorp/aws/latest)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Production-grade EKS platform on AWS, provisioned entirely through Terraform.

This repository is **Phase 1** of a portfolio project that deploys the **Instana Robot Shop** microservices application on Amazon EKS with a full GitOps, observability, and reliability stack.

> Companion repository: **robot-shop-gitops** — ArgoCD manifests, Helm values, and application deployment.

---

## Architecture

```text
                    ┌─────────────────────────────────────────────────┐
                    │            AWS Account 448049792905             │
                    │                                                 │
                    │  ┌─────────────────────────────────────────┐    │
                    │  │            VPC 10.0.0.0/16              │    │
                    │  │        us-east-1a / 1b / 1c             │    │
                    │  │                                         │    │
                    │  │  Public   → NAT + ALBs                  │    │
                    │  │  Private  → EKS 1.35 nodes + Karpenter  │    │
                    │  │  Intra    → RDS MySQL 8.0 (no egress)   │    │
                    │  │                                         │    │
                    │  │  VPC Endpoints: S3, ECR API/DKR, STS    │    │
                    │  └─────────────────────────────────────────┘    │
                    │                                                 │
                    │  KMS CMKs   → RDS / EBS / S3 (rotation on)      │
                    │  ECR        → 11 repos, immutable tags          │
                    │  ACM        → *.devopsportfolio.com wildcard    │
                    │  Route53    → devopsportfolio.com hosted zone   │
                    │  Secrets    → RDS credentials JSON              │
                    │  OIDC       → GitHub Actions federated identity │
                    └─────────────────────────────────────────────────┘
```

---

## Stack

| Layer | Technology | Version |
|---------|------------|---------|
| IaC | Terraform | >= 1.11 |
| Provider | hashicorp/aws | ~> 6.0 |
| Network | terraform-aws-modules/vpc | ~> 6.6 |
| Compute | terraform-aws-modules/eks | ~> 21.0 (v21.24.0) |
| Kubernetes | EKS | 1.35 |
| Autoscaling | Karpenter | v1.13.0 |
| Database | terraform-aws-modules/rds | ~> 7.2 (MySQL 8.0) |
| Registry | ECR | 11 microservice repos |
| DNS | Route53 | devopsportfolio.com |
| TLS | ACM | *.devopsportfolio.com wildcard |
| Secrets | AWS Secrets Manager | JSON-structured |
| Identity | GitHub OIDC | Federated, no static keys |

---

## Repository Structure

```text
robot-shop-infra/
├── .github/workflows/
│   ├── terraform-plan.yml
│   └── terraform-apply.yml
├── Docs/
│   └── security-audit.md
├── environments/prod/
│   ├── backend.tf
│   ├── providers.tf
│   ├── versions.tf
│   ├── variables.tf
│   ├── main.tf
│   └── outputs.tf
├── modules/
│   ├── kms/
│   ├── route53/
│   ├── vpc/
│   ├── eks/
│   ├── karpenter/
│   ├── rds-mysql/
│   ├── ecr/
│   ├── acm/
│   ├── secrets-manager/
│   └── github-oidc/
├── .pre-commit-config.yaml
├── .tflint.hcl
├── .trivyignore
└── Makefile
```

---

## Key Architectural Decisions

Every decision documented here is a deliberate trade-off between cost, complexity, and production readiness.

| Decision | Rationale |
|-----------|-----------|
| Single NAT Gateway | Saves ~$64/month vs one-per-AZ. Trade-off: if us-east-1a NAT fails, other AZs lose egress. Production: `one_nat_gateway_per_az = true`. |
| S3 Native State Locking | `use_lockfile = true` (Terraform ≥1.11) replaces the deprecated DynamoDB pattern. |
| EKS Pod Identity | Simpler than IRSA. Both can coexist. |
| Access Entries | Replaces deprecated `aws-auth` ConfigMap approach. |
| RDS in Intra Subnets | No internet route at all. |
| SG-to-SG Rules | Survives node IP changes without updates. |
| db.t4g.micro | Low-cost portfolio database (~$13/month). |
| MongoDB & Redis In-Cluster | Avoids additional managed service costs. |
| KMS CMKs | Enables key policy control and CloudTrail auditing. |
| ECR Immutable Tags | Prevents image tag overwrites. |
| Wildcard ACM Certificate | Covers all platform subdomains. |
| GitHub OIDC Federation | Eliminates long-lived AWS credentials. |
| Write-Only RDS Password | Password never stored in Terraform state. |

---

## CI/CD Pipeline

## terraform-plan.yml

Runs on every pull request.

### Validation

- `terraform fmt`
- `terraform validate`
- `tflint`
- Pre-commit hooks

### Security

- Trivy
- Checkov (HIGH/CRITICAL)

### Planning

- Terraform plan
- PR comment with plan output
- Infracost estimate

## terraform-apply.yml

Runs on merge to `main`.

### Deployment

- GitHub OIDC authentication
- Environment approval gate (`prod`)
- Concurrency locking
- Terraform apply

> No long-lived AWS credentials are stored in GitHub.

---

## Getting Started

## Prerequisites

- AWS account with admin credentials
- aws-cli >= 2.15
- terraform >= 1.11
- kubectl >= 1.35
- pre-commit >= 3.5
- Domain name delegated to Route53

## One-Time Bootstrap

```bash
# 1. Create Terraform state bucket
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="robotshop-tf-state-${ACCOUNT_ID}"

aws s3api create-bucket --bucket "$BUCKET" --region us-east-1

aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,\
IgnorePublicAcls=true,\
BlockPublicPolicy=true,\
RestrictPublicBuckets=true

# 2. Update backend.tf
sed -i '' "s/<YOUR_ACCOUNT_ID>/$ACCOUNT_ID/" environments/prod/backend.tf

# 3. Install hooks
pre-commit install
tflint --init --config=.tflint.hcl
```

## Deploy

```bash
cd environments/prod

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Configure kubectl:

```bash
aws eks update-kubeconfig \
  --name robot-shop \
  --region us-east-1

kubectl get nodes -o wide
```

Retrieve Route53 nameservers:

```bash
terraform output route53_name_servers
```

> Full deployment typically takes around 20 minutes.

---

## Teardown

## Full Destroy

```bash
make destroy
```

## Targeted Destroy

Preserves Route53, ACM, and GitHub OIDC resources.

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

---

## Security Posture

All findings from **tfsec**, **checkov**, and **trivy** are documented in:

```text
Docs/security-audit.md
```

Classification:

- Fixed
- False Positive
- Accepted Risk

## Findings Summary

| Tool | Findings | Fixed | False Positive | Accepted Risk |
|--------|----------|--------|----------------|---------------|
| tfsec | 30 | 1 | 12 | 17 |
| checkov | 25 | 0 | 9 | 16 |
| trivy | 0 | — | — | — |

---

## Cost

Estimated monthly cost with all resources running:

| Component | Cost |
|------------|------|
| EKS Control Plane | $73 |
| EKS Worker Nodes (2× t3.medium) | ~$60 |
| NAT Gateway | ~$32 + data |
| RDS db.t4g.micro | ~$13 |
| VPC Endpoints | ~$22 |
| EBS Storage (100GB gp3) | ~$8 |
| Route53 Hosted Zone | $0.50 |
| Everything Else | ~$5 |
| **Total** | **~$213/month** |

> Costs drop by approximately **$130/month** when using targeted destroy between work sessions.

---

## Contributing

This is a personal portfolio project, but issues and observations are welcome.

See:

```text
CONTRIBUTING.md
```

for contribution guidelines.

---

## License

MIT License

See:

```text
LICENSE
```

---

## Portfolio Context

This repository is **Phase 1** of a 10-phase platform engineering project.

### Phase 1
- Terraform-First: Building a Production-Grade EKS Platform ← *You are here*

### Phase 2
- Platform Engineering with ArgoCD App-of-Apps

### Phase 3
- Application Modernization: Moving Databases Out of Kubernetes

### Phase 4
- OIDC-Powered CI/CD: GitHub Actions to Argo Rollouts

### Phase 5
- Observability for Kubernetes: Beyond `kubectl logs`

### Phase 6
- Reliability Engineering: From "It Runs" to Production

### Phase 7
- Chaos Engineering on EKS: 8 Scenarios That Prove Your Platform

### Phase 8
- Disaster Recovery on EKS: Destroy Everything, Rebuild from Git

### Phase 9
- FinOps for DevOps Engineers: Optimizing EKS

### Phase 10
- Lessons Learned from Building a Production-Grade EKS Platform