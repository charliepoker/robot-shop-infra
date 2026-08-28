# Phase 2 — Platform Engineering: Handoff & Project State

**Status:** COMPLETE · tagged `v2.0.0` (both repos)
**Purpose:** durable record of everything built, decided, and learned in Phase 2, plus the exact starting context for Phase 3. Read this before resuming.

---

## 1. Fixed project facts (carry forward)

| Item | Value |
|---|---|
| AWS account | `448049792905` |
| Region | `us-east-1` |
| Domain | `devopsportfolio.com` (Route 53 public hosted zone, from Phase 1) |
| EKS cluster name | `robot-shop` |
| EKS version | 1.35 (`v1.35.6-eks-8f14419`) |
| Infra repo | `github.com/charliepoker/robot-shop-infra` (Terraform) |
| GitOps repo | `github.com/charliepoker/robot-shop-gitOps` |
| TF state bucket | `robotshop-tf-state-448049792905` (S3 native locking, `use_lockfile=true`) |
| Velero backup bucket | `robot-shop-velero-backups-448049792905` |
| RDS secret | `robot-shop/rds-credentials` (KMS-encrypted with S3 CMK) |
| Admin IAM user | `arn:aws:iam::448049792905:user/obinna` |
| CI role | `arn:aws:iam::448049792905:role/robot-shop-infra-github-actions` |

---

## 2. What Phase 2 delivered

Eight platform tools, all managed by ArgoCD App-of-Apps. **12 Applications total** (root + 11 children), all `Synced` + `Healthy`. Five controllers authenticate to AWS via **EKS Pod Identity** (zero static credentials).

### ArgoCD Applications (with actual chart versions)

| Application | Chart / version | Namespace | Sync wave | Notes |
|---|---|---|---|---|
| `root-app` | (raw manifest) | argocd | — | The one thing applied by hand |
| `aws-lb-controller` | `aws-load-balancer-controller` 3.4.1 | kube-system | -10 | `vpcId` pinned (IMDS workaround) |
| `external-dns` | 1.21.1 | external-dns | -10 | `policy: upsert-only`, `txtOwnerId: robot-shop` |
| `cert-manager` | v1.21.0 | cert-manager | -5 | DNS-01 via Route53 |
| `cert-manager-issuers` | (raw) | cert-manager | 0 | ClusterIssuers: staging + prod |
| `karpenter` | 1.7.1 (OCI `public.ecr.aws/karpenter/karpenter`) | kube-system | -5 | IAM/SQS from Phase 1 |
| `karpenter-nodepool` | (raw) | kube-system | 0 | NodePool + EC2NodeClass |
| `external-secrets` | 2.7.0 | external-secrets | -5 | ESO jumped to 2.x versioning |
| `external-secrets-store` | (raw) | external-secrets | 0 | ClusterSecretStore |
| `argo-rollouts` | 2.41.0 | argo-rollouts | -5 | For Phase 4 canary |
| `metrics-server` | 3.13.1 | kube-system | -5 | For HPA (Phase 6) |
| `velero` | 12.1.0 + plugin `velero-plugin-for-aws:v1.14.1` | velero | -5 | S3 backups |

ArgoCD itself: chart **10.1.3** (app v3.4.5), installed by hand (chicken-and-egg).

---

## 3. Files created

### Infra repo (`robot-shop-infra`) — new Terraform modules

```
modules/
├── aws-lb-controller/   main.tf, variables.tf, outputs.tf, iam-policy.json
├── external-dns/        main.tf, variables.tf, outputs.tf
├── cert-manager/        main.tf, variables.tf, outputs.tf
├── external-secrets/    main.tf, variables.tf, outputs.tf
└── velero-s3/           main.tf, variables.tf, outputs.tf
```

Each IAM module = `aws_iam_policy` + `aws_iam_role` (Pod Identity trust: `pods.eks.amazonaws.com`) + `aws_iam_role_policy_attachment` + `aws_eks_pod_identity_association`.

`environments/prod/main.tf` — added module calls: `aws_lb_controller`, `external_dns`, `cert_manager`, `external_secrets`, `velero`.

`modules/eks/main.tf` — **changed** (commit `c0ce12a`):
- `enable_cluster_creator_admin_permissions = false`
- `access_entries` built from `var.cluster_admin_principal_arns` (map: `ci_apply` + `obinna`), each granted `AmazonEKSClusterAdminPolicy` at cluster scope
- `kms_key_administrators = values(var.cluster_admin_principal_arns)`

`docs/` — added `teardown-and-rebuild.md`, `blog/phase-2-platform-engineering-argocd.md`, `diagrams/gitops-reconciliation.excalidraw`, this file.

### GitOps repo (`robot-shop-gitOps`)

```
argocd/
├── root-app.yaml                 # path: argocd/apps, directory.recurse: true
├── argocd-values.yaml            # ALB ingress, ACM cert ARN pinned, single-replica, server.insecure
├── apps/                         # 11 Application manifests (see table above)
└── manifests/
    ├── cert-manager/             clusterissuer-staging.yaml, clusterissuer-prod.yaml
    ├── karpenter/                ec2nodeclass.yaml, nodepool.yaml
    └── external-secrets/         clustersecretstore.yaml
```

---

## 4. AWS integration map (Pod Identity → IAM → service)

| Controller | ServiceAccount (ns) | IAM role | AWS permissions |
|---|---|---|---|
| aws-lb-controller | kube-system/aws-load-balancer-controller | `aws-lb-controller-robot-shop` | official LBC policy (ELB/EC2/ACM/WAF/Shield) |
| external-dns | external-dns/external-dns | `external-dns-robot-shop` | `route53:ChangeResourceRecordSets` on the zone + List* |
| cert-manager | cert-manager/cert-manager | `cert-manager-robot-shop` | route53 GetChange + Change/List on zone (DNS-01) |
| external-secrets | external-secrets/external-secrets | `external-secrets-robot-shop` | `secretsmanager:GetSecretValue` + **`kms:Decrypt`** |
| velero | velero/velero | `velero-robot-shop` | S3 object/bucket + **`kms:GenerateDataKey`** + EC2 snapshots |
| karpenter | kube-system/karpenter | (Phase 1) | EC2 fleet + SQS interruption queue `robot-shop` |
| ebs-csi | kube-system/ebs-csi-controller-sa | (Phase 1) | AmazonEBSCSIDriverPolicy |

---

## 5. Key decisions & trade-offs (interview-ready)

- **IAM in Terraform, deployment in GitOps.** AWS account-level resources (IAM roles, Pod Identity associations) live in `robot-shop-infra` and must survive a cluster rebuild. Controllers (Deployments) live in `robot-shop-gitOps` for continuous reconciliation. The ALB itself is in neither — the LB controller creates it dynamically from the Ingress.
- **Pod Identity, not IRSA.** Namespace+ServiceAccount → IAM role mapping, no OIDC annotation dance. Used for all 5 new controllers.
- **Two-Application split per tool with CRDs.** Chart at wave -5/-10, custom resources at wave 0. A ClusterIssuer/NodePool/ClusterSecretStore can't exist before its CRDs. Sync waves make ArgoCD wait for Healthy before the next wave.
- **cert-manager vs ACM.** ACM terminates TLS at the ALB (can't be mounted into pods); cert-manager issues in-cluster Secrets (mTLS, webhooks, portability). Not redundant — different layers.
- **Velero vs GitOps.** Git = desired state (ArgoCD rebuilds it). Velero = runtime state (PV data, ESO-materialized Secrets, cert-manager account keys). Four DR layers: Terraform / ArgoCD+Git / Velero / RDS snapshots.
- **Cost posture.** Single replicas across ArgoCD components; Karpenter Spot-preferred with on-demand fallback; NodePool `limits` ceiling; Velero S3 lifecycle expiry at 30 days.
- **`server.insecure: true`** on ArgoCD is correct — TLS terminates at the ALB with the ACM wildcard cert.

---

## 6. Gotchas & debugging lessons (do not re-learn these)

1. **EKS ships no ingress controller.** The AWS Load Balancer Controller is a separate install; it was missing from the original module list.
2. **`no EC2 IMDS role found` = "SDK found no credentials", not a network error.** Two different root causes hit this phase:
   - LB controller: genuine IMDS timeout auto-discovering VPC ID → **pin `vpcId` in Helm values**.
   - Velero: chart's SA is `velero-server` but the Pod Identity association was for `velero` → set `serviceAccount.server.name: velero` **and `kubectl rollout restart`** (Pod Identity injects creds at pod creation only).
3. **`root-app` stuck `Unknown`:** first the `main` branch didn't exist on the remote; then the live root-app still had stale `path: apps` after the repo was restructured to `argocd/apps`. `root-app` is the one thing ArgoCD can't self-heal.
4. **kubectl lockout (`the server has asked for the client to provide credentials`):** `enable_cluster_creator_admin_permissions` only granted admin to the CI role that ran apply, not `obinna`. Fixed via `aws eks create-access-entry`, then **codified in Terraform + `terraform import`** so it survives rebuilds.
5. **KMS permissions are separate from the service permission.** ESO needs `kms:Decrypt`; Velero needs `kms:GenerateDataKey`. Omitting them yields an opaque `AccessDenied` that looks like Secrets Manager / S3.
6. **Chart version drift.** ESO is now `2.7.0` (jumped to a 2.x scheme), ArgoCD `10.1.3`, cert-manager `v1.21.0`. Always `helm search repo <chart> --versions` before pinning.
7. **Distroless images have no shell.** `kubectl exec ... -- env` fails; inspect `spec.containers[0].env` via jsonpath instead.
8. **`kubectl get ingress` showing `PORTS: 80` is normal** for the annotation-driven ArgoCD chart — the 443 listener comes from the `listen-ports` annotation, not a `tls:` block. HTTPS still works.
9. **`certificate-arn: ""` triggers ACM auto-discovery by hostname** — it worked, but was pinned explicitly for determinism.

---

## 7. Verification — Phase 2 success criteria (all met)

- ✅ All 12 ArgoCD apps `Synced` + `Healthy`
- ✅ Karpenter provisions a **Spot** node in <60s; consolidates back in <90s
- ✅ `curl -I https://argocd.devopsportfolio.com` → `HTTP/2 200`, valid TLS
- ✅ Velero backup `Completed` (134 items), BSL `Available`
- ✅ cert-manager DNS-01 issuance tested end-to-end against `letsencrypt-staging` (challenge → TXT record → issued)
- ✅ ClusterSecretStore `Valid` / `ReadWrite`, ClusterIssuers both `Ready=True`

Health sweep command set is in `docs/teardown-and-rebuild.md` §6.

---

## 8. Teardown / rebuild (between work sessions)

Full runbook: `docs/teardown-and-rebuild.md`. Summary:

- **Destroy** (~$215/mo saved): `module.eks`, `module.karpenter`, `module.rds`, `module.vpc`.
- **Keep** (~$5/mo): Route53 zone, ACM cert, KMS CMKs, Velero bucket, ECR, Secrets Manager, GitHub OIDC, TF state.
- **Before destroy:** `kubectl -n argocd delete ingress argocd-server` (removes ALB), `kubectl delete nodepool --all` (drains Karpenter nodes), suspend root-app auto-sync. Otherwise: orphaned ALB + hung VPC destroy on dangling ENIs.
- **Rebuild:** `terraform apply` → `aws eks update-kubeconfig` → `helm install argocd ... -f argocd/argocd-values.yaml` → `kubectl apply -f argocd/root-app.yaml`.
- **⚠️ Manual step on rebuild:** update the pinned `vpcId` in `argocd/apps/aws-lb-controller.yaml` to the new VPC ID (`terraform output -raw vpc_id`). It's the only place infra state leaks into the GitOps repo.

---

## 9. Phase 3 starting context (Application Modernization)

Phase 3 deploys Robot Shop and wires the app to managed data. What's already in place for it:

| Phase 3 needs | Provided by Phase 2 | How to use |
|---|---|---|
| Secrets into pods | ESO + ClusterSecretStore `aws-secrets-manager` (Valid) | Create an `ExternalSecret` referencing `robot-shop/rds-credentials` → materializes a K8s Secret in `robot-shop` ns |
| App TLS cert | cert-manager + `letsencrypt-prod` ClusterIssuer | `Certificate` (or Ingress annotation) for `shop.devopsportfolio.com` — **this is cert-manager's first production issuance** |
| Public DNS + LB | ALB controller + ExternalDNS | Ingress with `alb` class + hostname annotation → ALB + Route53 record automatic |
| Managed DB | RDS from Phase 1 | ratings service connects to it |
| Autoscaling | Karpenter (nodes) + Metrics Server (for later HPA) | Karpenter already handles burst |

### ⚠️ IMPORTANT discrepancy to resolve in Phase 3

The 10-phase plan text says **RDS PostgreSQL 16** and "migrate ratings to PostgreSQL." **The actual Phase 1 infrastructure is RDS MySQL 8.0** (`module.rds-mysql`), and the Secrets Manager secret uses **`MYSQL_*` keys** (`MYSQL_HOST/PORT/DATABASE/USERNAME/PASSWORD`). Robot Shop's `ratings` service is natively MySQL, so MySQL is the sensible choice — but Phase 3 manifests, ExternalSecret keys, and any "PostgreSQL" references in the plan must be treated as **MySQL**. Decide explicitly and keep it consistent.

### Robot Shop data topology (per plan)
- `ratings` → **RDS MySQL** (managed) — the migration target
- `cart` → Redis (in-cluster, kept for cost)
- `catalogue`, `user` → MongoDB (in-cluster, kept)
- `dispatch` → RabbitMQ (in-cluster, kept)

### Not needed until later
- Argo Rollouts (installed now) → first used in **Phase 4** (canary on `user`)
- Metrics Server (installed now) → HPAs in **Phase 6**

---

## 10. Open items / tech debt carried into later phases

- **`vpcId` hardcoded** in `aws-lb-controller.yaml` — the one infra identifier in the GitOps repo. Ideal fix: template from a Terraform output in CI so rebuilds need no manual edit.
- **cert-manager production issuance** only proven via a throwaway staging cert; the first *prod* cert happens in Phase 3.
- **`argocd-values.yaml` cert ARN** is hardcoded — could later be injected via CI / External Secrets per the file's own comment.
- Working branch history used `chore/add-status-check` / `chore/ci-update-*`; ensure everything is merged to `main` (root-app tracks `main`).
