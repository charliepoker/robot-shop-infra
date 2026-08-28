# Teardown & Rebuild Runbook

**Purpose:** shut down the expensive infrastructure during a break, then bring it
back and resume where you left off — without losing certificates, DNS delegation,
backups, or Terraform state.

**Status when written:** end of Phase 2 (platform layer complete, `v2.0.0`).
**Last updated:** end of Phase 3 (Robot Shop deployed, app live at
`shop.devopsportfolio.com`). See the change note below.

> **Phase 3 update note.** Six things changed since this was written at end of
> Phase 2, all reflected below:
> 1. **Destroy target list corrected.** The old §3 destroyed only 4 modules and
>    its keep-list contradicted the working command. Resolved: destroy
>    `secrets_manager` **with** `rds` (they're now coupled — see below), keep
>    `kms` and `ecr` (destroying KMS triggers a 7-day deletion window; ECR is
>    free and Phase 4 fills it).
> 2. **RDS master password is now RDS-managed** (`manage_master_user_password`)
>    and mirrored into `robot-shop/rds-credentials`. This changes the rebuild
>    credential flow — see §5.
> 3. **Per-app secrets** (`ratings-db`, `shipping-db`, `recovery_window = 0`)
>    now exist; post-teardown check added for scheduled-deletion ghosts.
> 4. **gp3 StorageClass + redis PVC** now exist; redis's EBS volume is deleted
>    on teardown (disposable cache) — noted in §5.
> 5. **ratings/shipping intentionally CrashLoop** until the Phase 4 image;
>    expected on every rebuild, not a failure.
> 6. **App-deploy steps added** (§4f, §4g): the Robot Shop application layer —
>    secrets, schema bootstrap Job, the 22 app manifests, the Ingress, and the
>    one-time cities seed — now has an explicit rebuild walkthrough so the app
>    reaches its URL.

---

## 1. What gets destroyed vs. what stays

The split is deliberate. Anything **expensive and reproducible** goes; anything
**cheap and painful-to-recreate** stays.

### Destroyed (~$215/month saved)

| Resource | Module | Approx. cost |
|---|---|---|
| EKS control plane | `module.eks` | ~$73/mo |
| Managed node group (2× t3.medium) | `module.eks` | ~$60/mo |
| NAT Gateway | `module.vpc` | ~$32/mo + data |
| VPC interface endpoints (ECR api/dkr, STS) | `module.vpc` | ~$21/mo |
| RDS MySQL `db.t4g.micro` | `module.rds` | ~$13/mo |
| ALB (created by the LB controller, **not** Terraform) | — | ~$16/mo |
| Karpenter IAM/SQS | `module.karpenter` | ~$0 |
| Pod Identity associations (all controllers) | cascade | $0 |

### Kept (~$5–6/month)

| Resource | Module | Why it must survive |
|---|---|---|
| **Route 53 hosted zone** | `module.route53` | Destroying it issues **new NS records**. Your registrar's delegation would break and the `hostedZoneID` hardcoded in the cert-manager ClusterIssuers would go stale. ~$0.50/mo. |
| **ACM wildcard certificate** | `module.acm` | Free. Its ARN is referenced in `argocd-values.yaml`. Recreating it means a new ARN and re-validation. |
| **KMS CMKs** (rds, ebs, s3) | `module.kms` | ~$1/key/mo. Deletion has a 7–30 day waiting period and would orphan anything encrypted with them. |
| **Terraform state bucket + lock table** | bootstrap | Obvious. Not managed by this stack. |
| **Velero backup bucket** | `module.velero` | Contains your backups. The whole point is that backups outlive the cluster. |
| **ECR repositories** | `module.ecr` | Images + lifecycle policies. Storage is negligible, and once Phase 4 CI runs, destroying ECR would force a CI run before every rebuild can deploy. Repos are `IMMUTABLE` — `force_delete` would be needed to destroy non-empty ones. **Keep.** |
| **GitHub OIDC provider + CI role** | `module.github_oidc` | Needed by CI; free; recreating churns trust config. |
| **IAM roles/policies for controllers** | various | Free. Only their *Pod Identity associations* are destroyed with the cluster. |

> **Moved OUT of the keep list in Phase 3: `module.secrets_manager`.** It used to
> be a simple hand-seeded credential, safe to preserve. It is now coupled to RDS:
> `robot-shop/rds-credentials` mirrors the RDS-managed master secret, and the
> per-app secrets are generated alongside. Keeping `secrets_manager` while
> destroying `rds` leaves the mirror pointing at a deleted managed secret (a
> dangling reference until the next apply). So it is now **destroyed together
> with `rds`** — cleaner lifecycle, and the app secrets regenerate on rebuild.

---

## 2. Pre-destroy cleanup (DO NOT SKIP)

Two categories of AWS resources exist that **Terraform does not know about**,
because they were created by in-cluster controllers. If you skip this, the VPC
destroy will hang or fail on dangling ENIs, and you'll keep paying for an
orphaned ALB.

### 2a. Optional: take a final Velero backup

```bash
velero backup create pre-teardown-$(date +%Y%m%d) --wait
velero backup get
```

Not strictly needed — everything is in Git — but it's a free rehearsal for the
Phase 8 restore drill.

### 2b. Delete the ALB by removing the Ingress

The AWS Load Balancer Controller created the ALB. It only deletes the ALB when
the Ingress goes away, and the controller must still be running to do it.

```bash
# Remove the ArgoCD Ingress -> controller deletes the ALB
kubectl -n argocd delete ingress argocd-server

# Confirm the ALB is actually gone before continuing
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName,'argocd')].LoadBalancerName" \
  --output text
```

Wait until that returns empty. If you destroy the cluster first, the controller
dies with it and the ALB is orphaned — you'd have to delete it by hand.

### 2c. Remove Karpenter-provisioned nodes

Karpenter-launched EC2 instances are not in Terraform state. Delete the NodePool
so Karpenter drains and terminates them itself.

```bash
kubectl delete nodepool --all
kubectl delete ec2nodeclass --all

# Confirm only the managed node group nodes remain
kubectl get nodes
```

### 2d. Suspend Argo CD auto-sync (prevents fighting the teardown)

```bash
kubectl -n argocd patch application root-app \
  --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
```

Optional but avoids Argo CD re-creating things mid-destroy.

---

## 3. The targeted destroy

```bash
cd environments/prod

# ALWAYS review the plan first — confirm nothing in the "keep" list appears
terraform plan -destroy \
  -target=module.eks \
  -target=module.karpenter \
  -target=module.rds \
  -target=module.secrets_manager \
  -target=module.vpc \
  -out=destroy.tfplan
```

**Note the 5 targets.** `secrets_manager` is included (coupled to RDS since
Phase 3 — see §1). `kms` and `ecr` are deliberately **excluded**: destroying KMS
starts a 7–30 day key-deletion window that fights the next rebuild, and ECR is
free to keep and will hold your images after Phase 4.

**Review the plan output carefully.** You should see the cluster, node group,
NAT gateway, subnets, VPC endpoints, RDS instance, the Secrets Manager secrets,
and the Pod Identity associations. You should **NOT** see: the Route 53 zone,
the ACM cert, **KMS keys**, **ECR repositories**, the Velero S3 bucket, or the
GitHub OIDC provider.

Then apply it:

```bash
terraform apply destroy.tfplan
```

> **Cascade note:** Terraform destroys resources that *depend on* the targets.
> That means the Pod Identity associations inside `module.aws_lb_controller`,
> `module.external_dns`, `module.cert_manager`, `module.external_secrets`, and
> `module.velero` are removed too (they reference the cluster), but the IAM roles,
> policies, and the **Velero S3 bucket survive** — they don't depend on the cluster.
> `module.secrets_manager` is now an explicit destroy target (coupled to RDS),
> so its secrets are removed rather than refreshed — they regenerate on rebuild
> with fresh per-app passwords, and `robot-shop/rds-credentials` re-mirrors from
> the new RDS-managed secret.

### If the VPC destroy hangs

Almost always a dangling ENI from the ALB or a leftover Karpenter node:

```bash
aws ec2 describe-network-interfaces \
  --filters Name=vpc-id,Values=$(terraform output -raw vpc_id) \
  --query 'NetworkInterfaces[].{ID:NetworkInterfaceId,Desc:Description,Status:Status}' \
  --output table
```

Delete any `available` (unattached) ENIs, then re-run the destroy.

### Verify the spend actually stopped

```bash
aws eks list-clusters
aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier'
aws ec2 describe-nat-gateways --filter Name=state,Values=available \
  --query 'NatGateways[].NatGatewayId'
aws ec2 describe-instances \
  --filters Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].InstanceId'
```

All should be empty.

### Post-teardown: secret ghosts and orphaned volumes (Phase 3 additions)

**Scheduled-deletion secrets.** The app secrets use `recovery_window = 0`, so
they hard-delete and their names free up immediately. Verify none is stuck, or
the next apply fails with "already scheduled for deletion":

```bash
aws secretsmanager list-secrets --include-planned-deletion \
  --query "SecretList[?starts_with(Name,'robot-shop/')].[Name,DeletedDate]" --output table
# any DeletedDate → force-delete before rebuilding:
aws secretsmanager delete-secret --secret-id robot-shop/ratings-db  --force-delete-without-recovery
aws secretsmanager delete-secret --secret-id robot-shop/shipping-db --force-delete-without-recovery
```

**Orphaned EBS volumes.** redis's PVC has `reclaimPolicy: Delete`, so its volume
goes with the cluster — but failed provisioning attempts can leave unattached
volumes that bill:

```bash
aws ec2 describe-volumes --filters Name=status,Values=available \
  --query 'Volumes[].{id:VolumeId,size:Size,created:CreateTime}' --output table
# delete each confirmed orphan: aws ec2 delete-volume --volume-id vol-xxxxx
```

---

## 4. Rebuild

### 4a. Recreate the infrastructure

```bash
cd environments/prod
terraform plan -out=tfplan     # expect ~the resources you destroyed, nothing else
terraform apply tfplan
```

This restores the VPC, EKS, node group, RDS, Karpenter IAM/SQS, and **all Pod
Identity associations** — including the `obinna` cluster-admin access entry,
because that's codified in `modules/eks` (`cluster_admin_principal_arns`).
No manual `aws eks create-access-entry` needed this time.

### 4b. Reconnect kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name robot-shop
kubectl get nodes    # expect 2 Ready
```

### 4c. Bootstrap Argo CD (the chicken-and-egg step)

Argo CD can't deploy itself, so this one install is always manual:

```bash
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update

kubectl create ns argocd

helm install argocd argo/argo-cd --version 10.1.3 -n argocd \
  -f argocd/argocd-values.yaml        # path relative to robot-shop-gitOps
```

### 4c-bis. Update the pinned `vpcId` BEFORE syncing the root app

The VPC has a new ID. `argocd/apps/aws-lb-controller.yaml` hardcodes the old one
and must be updated first, or the LB controller crash-loops and no ALB is created.

```bash
cd environments/prod && terraform output -raw vpc_id
# edit robot-shop-gitOps/argocd/apps/aws-lb-controller.yaml -> vpcId: <new value>
# commit + push to main
```

See section 5 for the full explanation.

### 4d. Apply the root app — everything else follows

```bash
kubectl apply -f argocd/root-app.yaml
```

Argo CD now reconciles all 11 child applications from Git. Watch:

```bash
kubectl -n argocd get applications -w
```

Expect all Synced + Healthy within ~10–15 minutes. Sync waves handle ordering
(cert-manager and Karpenter controllers at wave `-5`, their CRs at wave `0`).

### 4e. Get the new Argo CD admin password

Regenerated on every fresh install:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

### 4f. Deploy the Robot Shop application (Phase 3)

This is the step that makes `shop.devopsportfolio.com` load in a browser. The
application deploys **automatically** once the root app syncs — the
`robot-shop-secrets`, `storage`, and `robot-shop` child apps are already in
`argocd/apps/` and reconcile from Git, so there is no manual `kubectl apply` of
the app itself. But the layer has a required internal order and two things gate
it, so verify each step rather than assuming.

**The dependency chain (enforced by sync-waves, but confirm it):**

```
platform (ESO, LB controller, cert-manager, ExternalDNS, storage class)
  |-> robot-shop-secrets app
  |     - namespaces: robot-shop, robot-shop-bootstrap        (wave -1)
  |     - ExternalSecrets: rds-master (bootstrap ns),
  |                        ratings-db, shipping-db (app ns),
  |                        ratings-db-bootstrap, shipping-db-bootstrap (bootstrap ns)
  |     - ServiceAccount: rds-schema-bootstrap                (wave -2)
  |     - PreSync Job: rds-schema-bootstrap  (creates DBs, users, grants)
  |-> robot-shop app
        - 22 manifests: web, cart, catalogue, user, payment, dispatch,
          ratings, shipping, mongodb, redis(StatefulSet), rabbitmq + services + ingress
```

**Step 1 — confirm the storage class exists first.** The redis StatefulSet's PVC
binds to `gp3`. If the `storage` app hasn't synced, redis stays `Pending` and
takes cart down with it.

```bash
kubectl get sc gp3    # must exist, provisioner ebs.csi.aws.com, (default)
```

**Step 2 — confirm all five ExternalSecrets synced.** This is the gate for the
bootstrap Job: it needs `rds-master` (to connect) and the two `-bootstrap`
secrets (to set the app-user passwords).

```bash
kubectl get externalsecret -A
# expect SecretSynced/True for: rds-master, ratings-db-bootstrap,
# shipping-db-bootstrap (robot-shop-bootstrap ns); ratings-db, shipping-db (robot-shop ns)
```

If any are missing, the most common cause is the ESO IAM policy not covering the
new secret ARNs, or a scheduled-deletion ghost from teardown (see §3
"post-teardown"). Fix before proceeding — the Job fails without them.

**Step 3 — confirm the schema bootstrap Job completed.** It runs as a PreSync
hook before the app pods and creates the `ratings` and `cities` databases, their
least-privilege users, and grants. Idempotent, so it's safe on every rebuild.

```bash
kubectl get job rds-schema-bootstrap -n robot-shop-bootstrap    # COMPLETIONS 1/1
kubectl logs -n robot-shop-bootstrap job/rds-schema-bootstrap   # "Schema bootstrap complete."
```

If it's stuck on `Access denied`: the Job connects as the RDS master. A fresh
instance + fresh mirror should match, but if the mirror hasn't caught up, force
an ESO refresh and let the Job retry:

```bash
kubectl annotate externalsecret rds-master -n robot-shop-bootstrap \
  force-sync=$(date +%s) --overwrite
kubectl delete job rds-schema-bootstrap -n robot-shop-bootstrap   # ArgoCD recreates it
```

**Step 4 — watch the app pods.** Once the Job completes, the `robot-shop` app
syncs its 22 manifests.

```bash
kubectl get pods -n robot-shop -w
```

**Expected: 10 Running, 2 CrashLoop (by design).**
- Running: web, cart, catalogue, user, payment, dispatch, mongodb, redis, rabbitmq.
- CrashLoop: **ratings, shipping** — upstream images hardcode DB creds and can't
  auth against the ESO-set passwords. **This is expected until the Phase 4 image.**
  If you parked them at `--replicas=0` before teardown, scale back up:
  `kubectl scale deploy/ratings deploy/shipping -n robot-shop --replicas=1`.

**Step 5 — confirm the storefront is reachable in a browser.** The `robot-shop`
app includes the Ingress; the LB controller provisions an ALB and ExternalDNS
creates the `shop` record. Allow 2–3 min for the ALB, then ~1–5 min for DNS.

```bash
kubectl get ingress -n robot-shop        # ADDRESS populates with the ALB DNS name
dig +short shop.devopsportfolio.com       # resolves to the ALB
curl -sI https://shop.devopsportfolio.com # HTTP/2 200
```

Then open `https://shop.devopsportfolio.com` — the storefront loads with a valid
wildcard cert. Categories, cart, and login work; ratings/shipping features are
the two down until Phase 4.

> **Fresh-rebuild reminder.** All of the above assumes the app manifests are
> committed to `main` in `robot-shop-gitOps` (they are, as of Phase 3). If you
> ever start from a repo state that predates Phase 3, none of these apps exist to
> sync — the platform comes up healthy but `robot-shop` is simply absent. Verify
> `argocd/apps/` contains `robot-shop.yaml`, `robot-shop-secrets.yaml`, and
> `storage.yaml` before expecting the app.

### 4g. One-time only: seed the cities data

**Skip this on a normal rebuild.** The `cities` table (~948k rows, 64.5 MB) is
loaded **once** and captured in a manual RDS snapshot, then restored on
subsequent rebuilds rather than re-imported (it's slow on `db.t4g.micro` and
would threaten the Phase 8 <45-min target).

- **First-ever bring-up, or any rebuild from an unseeded/empty instance with no
  snapshot:** run `runbooks/09-seed-cities-data.md` to load the data, then
  `aws rds create-db-snapshot`.
- **Every rebuild after a seeded snapshot exists:** restore the snapshot (§6
  "If cities was previously seeded") instead of running this.

Until `cities` is seeded, `shipping`'s city lookups return empty — harmless for
the rest of the app, and `shipping` is CrashLooping pre-Phase-4 anyway.

---

## 5. What changes on rebuild (and what doesn't)

### Handles itself — no action needed

| Thing | Why it's fine |
|---|---|
| **ACM certificate / ALB TLS** | The cert was never destroyed. Same ARN, still in `argocd-values.yaml`, still valid. **This is the main reason `module.acm` is on the keep list.** |
| **DNS record for argocd** | New ALB = new DNS name, but ExternalDNS upserts the Route 53 record automatically within ~1 min of the Ingress coming back. |
| **cert-manager ClusterIssuers** | `hostedZoneID` is unchanged because the zone survived. Issuers re-register a new ACME account key and go `Ready` on their own. |
| **RDS credentials** | RDS gets a new endpoint. The **master password is now RDS-managed** (`manage_master_user_password`): RDS generates it and writes it to an AWS-managed secret at instance creation, and Terraform mirrors it into `robot-shop/rds-credentials` in the same apply. Instance and secret cannot drift. ESO re-syncs into the cluster. The **per-app** `ratings`/`shipping` passwords are freshly generated by `module.secrets_manager` and applied to the MySQL users by the idempotent PreSync bootstrap Job. No manual step. |
| **Schema bootstrap** | The `rds-schema-bootstrap` PreSync Job re-creates the `ratings`/`cities` databases, users, and grants idempotently on every sync. On a fresh (unseeded) RDS it runs clean; there is nothing to restore unless `cities` was previously seeded (see §5 "RDS data"). |
| **redis PVC** | New EBS volume on the `gp3` StorageClass (aws/ebs key). Cart cache is disposable, so losing the old volume is expected and harmless. |
| **Karpenter node role** | Pinned to `robot-shop-karpenter-node` (`node_iam_role_use_name_prefix = false`), so the `EC2NodeClass` manifest still matches. |
| **Velero backup bucket** | Name includes the account ID and never changed. The BackupStorageLocation reconnects and syncs existing backups. |
| **`obinna` cluster access** | Codified in Terraform. Recreated automatically. |
| **Discovery tags** | VPC subnet/SG tags (`karpenter.sh/discovery`) are recreated identically by `module.vpc`. |

### Expect these to change

| Thing | Impact |
|---|---|
| **Argo CD admin password** | New. Fetch it (4e). |
| **ALB DNS name** | New hostname; ExternalDNS fixes the record. Only matters if you hardcoded the ALB name anywhere (you didn't). |
| **EKS OIDC provider URL** | New. Harmless — everything uses Pod Identity, not IRSA. |
| **VPC / subnet / security-group IDs** | All new. Harmless for Karpenter and the ALB controller because they discover by **tag** (`karpenter.sh/discovery`, `kubernetes.io/role/elb`), not by ID — and `module.vpc` recreates those tags identically. CIDRs are unchanged (`10.0.0.0/16` is a variable). **One exception — see below.** |
| **NAT Gateway public IP (EIP)** | New. Only matters if an external system allowlisted the old egress IP. Nothing here does. |
| **cert-manager ACME account key** | New account registered with Let's Encrypt. Harmless. |
| **RDS data** | **Gone by default.** `skip_final_snapshot = true`. The `ratings` schema is tiny and re-created by the bootstrap Job, so losing it is fine. The **`cities` seed** (~948k rows) is the exception: it is loaded once out-of-band and captured in a **manual snapshot** (runbook `09-seed-cities-data.md`). Manual snapshots survive instance deletion, so a seeded snapshot persists across teardown — but you must **restore it deliberately** on rebuild (see §5 "cities seed" below); a plain apply gives a fresh empty instance. If `cities` was never seeded, there is nothing to protect. |
| **In-cluster Secrets / PVC data** | Gone unless restored from a Velero backup. redis cart cache is disposable by design. |

### Watch out for

**⚠️ The pinned `vpcId` in the AWS Load Balancer Controller — MUST be updated after rebuild.**

This is the single stale reference in the whole stack. `argocd/apps/aws-lb-controller.yaml`
hardcodes the VPC ID:

```yaml
        vpcId: vpc-xxxxxxxxxxxxx   # stale after VPC recreation
```

It was pinned deliberately (auto-discovery via EC2 IMDS times out from pods on
EKS), but that means a recreated VPC leaves it pointing at nothing. The controller
fails to start with:

```
unable to initialize AWS cloud: failed to get VPC ID ...
```

**Fix immediately after `terraform apply`, before the root app syncs:**

```bash
# get the new VPC ID
cd environments/prod && terraform output -raw vpc_id

# update robot-shop-gitOps/argocd/apps/aws-lb-controller.yaml with that value
git add argocd/apps/aws-lb-controller.yaml
git commit -m "Update vpcId after VPC rebuild"
git push origin main
```

If the root app already synced with the stale value, force a re-read after pushing:

```bash
kubectl -n argocd annotate application aws-lb-controller \
  argocd.argoproj.io/refresh=hard --overwrite
kubectl -n kube-system rollout restart deploy/aws-lb-controller-aws-load-balancer-controller
```

Everything downstream depends on this — no LB controller means no ALB, which
means no Ingress, which means `argocd.devopsportfolio.com` never comes back.

> **Improvement worth making:** this is the one place the GitOps repo holds an
> infrastructure identifier. A cleaner long-term fix is to stop hardcoding it —
> either drop `vpcId` and give the controller a way to resolve it that doesn't
> depend on IMDS, or template it from a Terraform output during CI. Until then,
> treat it as a manual post-rebuild step.

**Let's Encrypt rate limits.** If you tear down and rebuild repeatedly *and* have
real Certificates pointing at `letsencrypt-prod`, you can burn the 50-certs-per-
registered-domain-per-week limit. Test against `letsencrypt-staging` when
iterating.

**RDS data after Phase 3.** Once the app has data, take a snapshot before
destroying:
```bash
aws rds create-db-snapshot \
  --db-instance-identifier <id> \
  --db-snapshot-identifier pre-teardown-$(date +%Y%m%d)
```
Restoring from it is a different path than a clean `terraform apply` — see
runbook `02-restore-rds.md`.

---

## 6. Post-rebuild verification

Same sweep that closed Phase 2:

```bash
kubectl -n argocd get applications          # all Synced + Healthy
curl -I https://argocd.devopsportfolio.com  # HTTP/2 200
kubectl get clusterissuer                   # both True
kubectl get clustersecretstore              # Valid
kubectl get nodepool,ec2nodeclass           # both True
velero backup-location get                  # Available
kubectl get pods -A | grep -vE 'Running|Completed'
```

### Application layer (Phase 3)

Once the platform is Healthy, the `robot-shop`, `robot-shop-secrets`, and
`storage` apps sync automatically. Confirm:

```bash
kubectl get externalsecret -A                                   # all SecretSynced/True
kubectl get job rds-schema-bootstrap -n robot-shop-bootstrap    # Completed
kubectl get pods -n robot-shop
kubectl get ingress -n robot-shop                               # ADDRESS = ALB (2-3 min)
curl -sI https://shop.devopsportfolio.com                       # HTTP/2 200
```

**Expected pod state:**
- Running: web, cart, catalogue, user, payment, dispatch, mongodb, redis, rabbitmq
- **CrashLoop (expected, NOT a failure): ratings, shipping** — the upstream
  images hardcode DB credentials and can't auth against the ESO-set passwords.
  They go green only once the **Phase 4** patched image ships. If you parked them
  at `--replicas=0` before teardown, scale them back up to `1`.

**If `cities` was previously seeded:** restore the seeded snapshot instead of
leaving the fresh empty instance —

```bash
# see runbook 09; restore the most recent robot-shop-mysql-seeded-* snapshot,
# then point the app at it. Otherwise shipping's city lookups return empty.
aws rds describe-db-snapshots --db-instance-identifier robot-shop-mysql \
  --query 'DBSnapshots[?starts_with(DBSnapshotIdentifier,`robot-shop-mysql-seeded`)].DBSnapshotIdentifier'
```

When all of that passes, you're back to a fully deployed app at
`shop.devopsportfolio.com` (minus ratings/shipping until Phase 4).

---

## 7. Interview framing

This teardown/rebuild cycle *is* the Phase 7 cluster-rebuild scenario in
disguise — time it and you get the metric for free.

- "Everything except DNS, certs, backups, and state is disposable. A rebuild is
  `terraform apply` plus one `kubectl apply` of the root app — roughly 15 minutes
  of infra plus 10 of reconciliation."
- "I deliberately kept Route 53 and ACM out of the teardown. Destroying the zone
  would reissue NS records and break registrar delegation; destroying the cert
  would change the ARN referenced in the Argo CD Ingress. Cheap to keep, painful
  to recreate."
- "The ALB and Karpenter nodes aren't in Terraform state — they're created by
  in-cluster controllers. You have to remove the Ingress and NodePool *before*
  destroying the cluster, or you orphan an ALB and hang the VPC destroy on
  dangling ENIs. That ordering problem is the thing people miss."