# Homelab Backlog

Findings from security + architecture audit. Grouped by severity.

---

## Critical

- [ ] **Pin Cilium Helm chart version**
  - `apps/core/cilium/kustomization.yaml` — `helmCharts` block has no `version:` field.
  - CNI inflates whatever is latest from `https://helm.cilium.io/` on each build.
  - Fix: run `helm ls -n kube-system` to find deployed version, add `version: <x.y.z>` to the helmChart entry.

- [ ] **Remove RBAC write from ArgoCD ClusterRole**
  - `apps/core/argocd/namespace.yaml:46-48` — ArgoCD can create/patch/delete ClusterRoles and ClusterRoleBindings.
  - This is cluster-admin via RBAC escalation regardless of the removed explicit binding.
  - Fix: remove `clusterroles` and `clusterrolebindings` from the `rbac.authorization.k8s.io` write rules. Namespace-scoped `roles`/`rolebindings` only.

- [ ] **Enable TLS on Bitwarden SDK server + add NetworkPolicy to external-secrets namespace**
  - `apps/core/external-secrets/values.yaml` — `bitwarden-sdk-server.image.tls.enabled: false`.
  - No NetworkPolicy in `external-secrets` namespace. Any pod can hit `http://bitwarden-sdk-server.external-secrets.svc.cluster.local:9998` and extract all secrets in plaintext.
  - Fix part 1: set `tls.enabled: true` in values.yaml and update `ClusterSecretStore` to use `https://`.
  - Fix part 2: add `default-deny-all` + explicit allow (ESO controller → SDK server only) NetworkPolicy to `external-secrets` namespace.

- [ ] **Replace placeholder UUIDs in smb-creds ExternalSecret**
  - `apps/core/external-secrets/smb-creds.yaml` — `key: "<REPLACE-WITH-BSM-UUID-FOR-SMB-USERNAME>"` committed to git.
  - ESO fails to sync every hour. `smb-creds` Secret never materializes. PVC mount fails. filebrowser pod stuck.
  - Fix: add real BSM UUIDs. If UUIDs are sensitive, use a kustomize secretGenerator with a `.gitignore`d patch file, or document the required Bitwarden item names so they can be reconstructed on cluster rebuild.

---

## High

- [ ] **Add `StorageClass: photos-pv` manifest to git**
  - `apps/core/storage/volumes.yaml:12` and `apps/media/filebrowser/pvc-photos.yaml:10` both reference `storageClassName: photos-pv`.
  - No StorageClass resource exists anywhere in the repo. Created out-of-band. Cluster is not fully rebuildable from git.
  - Fix: create `apps/core/storage/storageclass.yaml` with `provisioner: smb.csi.k8s.io`, `volumeBindingMode: Immediate`. Add to `storage/kustomization.yaml` resources.

- [ ] **Add persistent `/config` volume to filebrowser**
  - `apps/media/filebrowser/deployment.yaml` — only mounts `/data` (read-only photos). No `/config` mount.
  - `hurlenko/filebrowser` writes its database to `/database.db` (or `/config/`) by default. On the current setup this is ephemeral. Every pod restart wipes all users, bookmarks, settings.
  - Fix: create an SMB-backed PV/PVC for filebrowser config (writable). Mount at `/config`. Add `--database /config/filebrowser.db` to container args.

- [ ] **Add ingress NetworkPolicy to filebrowser + restrict LoadBalancer source range**
  - `apps/media/filebrowser/networkpolicy.yaml` — `policyTypes: [Egress]` only. No ingress restriction.
  - `apps/media/filebrowser/service.yaml` — `type: LoadBalancer` with no `loadBalancerSourceRanges`.
  - Any device on the LAN reaches filebrowser. Default credentials are `admin`/`admin`.
  - Fix part 1: add `Ingress` to `policyTypes` and an ingress rule in NetworkPolicy.
  - Fix part 2: add `loadBalancerSourceRanges: ["192.168.1.0/24"]` (or tighter) to the Service.
  - Fix part 3: mount a filebrowser config that overrides the default admin password, or document mandatory first-boot credential rotation.

- [ ] **Gate PR merges on CI — add branch protection and `pull_request:` trigger**
  - `.github/workflows/linters.yaml` — `on: push: {}` fires after merge, not before.
  - No branch protection on `main`. Bad manifests merge freely.
  - Fix: change trigger to include `pull_request:`. Enable branch protection on `main`: require status checks, require PR approval, no direct push.

- [ ] **Fix Taskfile validation tasks swallowing exit codes**
  - `Taskfile.yml` — every `kustomize build`, `kubeconform`, `kube-linter`, `polaris` call uses `|| printf "❌ Failed"` which exits 0 on failure.
  - `task validate` returns success even when manifests are broken.
  - Fix: replace `|| printf` with `|| { printf "❌ Failed %s\n" "{{.ITEM}}"; exit 1; }` in each task.

- [ ] **Add CRD schema sources to kubeconform — remove `-ignore-missing-schemas`**
  - `Taskfile.yml` — validate-schema task uses `-ignore-missing-schemas`.
  - All CRDs (ArgoCD, ESO, Cilium) are silently skipped. The validate step doesn't validate the most interesting resources.
  - Fix: add `-schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'` and remove `-ignore-missing-schemas`.

- [ ] **Pin GitHub Actions to commit SHAs**
  - `.github/workflows/linters.yaml` — `actions/checkout@v5`, `ibiqlik/action-yamllint@v3`, `DavidAnson/markdownlint-cli2-action@v21`, `arduino/setup-task@v2` all use mutable version tags.
  - Supply chain risk: tag can be repointed to malicious code with `GITHUB_TOKEN` access.
  - Fix: replace each `@vN` with a full SHA digest. Add `github-actions` group to Renovate to keep SHAs current.

- [ ] **Prune polaris.yaml — remove AWS/EKS/Datadog exemptions that don't apply**
  - `.config/polaris.yaml` — exempts `aws-iam-authenticator`, `kube2iam`, `ebs-csi-controller`, `datadog`, `local-path-provisioner`, `tiller`, `kops-controller`, and 30+ others that don't exist in this cluster.
  - Polaris config is copy-pasted boilerplate. Gives false confidence. Hides real issues by diluting the signal.
  - Fix: delete all exemptions for components not in this cluster. Keep only: `cilium`, `hubble-*`, `coredns`, `argocd-*`, `external-secrets`.

---

## Medium

- [ ] **Add default-deny NetworkPolicy to all core namespaces**
  - `core-argocd`, `external-secrets`, `core-secrets`, `kube-system` have no NetworkPolicy.
  - Lateral movement after any pod compromise is unrestricted. ArgoCD gRPC, Bitwarden SDK server, and materialized secrets are reachable from any namespace.
  - Fix: add a `default-deny-all` NetworkPolicy to each core namespace, then add explicit allow rules for required traffic paths only.

- [ ] **Configure ArgoCD OIDC / SSO**
  - `apps/core/argocd/argocd-cm.yaml` — no `oidc.config` or Dex configuration.
  - All users share a single `admin` account. No audit trail.
  - Fix short-term: set a strong `admin` password via bootstrapped Secret. Fix long-term: configure GitHub OAuth via Dex or deploy Authentik (planned feature).

- [ ] **Verify and fix filebrowser `runAsNonRoot: true` — add explicit `runAsUser`**
  - `apps/media/filebrowser/deployment.yaml` — `runAsNonRoot: true` with no `runAsUser`.
  - If `hurlenko/filebrowser:v2` image has `USER root` (or no USER), pod crashes with `container has runAsNonRoot and image has non-numeric user`.
  - Fix: run `docker inspect hurlenko/filebrowser:v2 --format='{{.Config.User}}'`. If root/empty, add `runAsUser: 1000`. Also add `readOnlyRootFilesystem: true` (after adding the `/config` persistent volume).

- [ ] **Delete orphaned ArgoCD vendored chart**
  - `apps/core/argocd/charts/argo-cd-9.5.9/` — vendored Helm chart that is not used.
  - `kustomization.yaml` installs ArgoCD from `github.com/argoproj/argo-cd//manifests/cluster-install`, not from the local chart.
  - The directory implies Helm install is active. It is not. It's dead weight and confusion.
  - Fix: `git rm -r apps/core/argocd/charts/`.

- [ ] **Set `strategy: Recreate` on filebrowser Deployment**
  - `apps/media/filebrowser/deployment.yaml` — no `strategy:` field. Defaults to `RollingUpdate` with `maxUnavailable: 25%` = 1 for single replica.
  - Every update causes downtime. `RollingUpdate` on `replicas: 1` is just `Recreate` with a misleading name.
  - Fix: add `spec.strategy.type: Recreate`.

- [ ] **Remove dead `YAMLFIX_IMAGE` variable from Taskfile**
  - `Taskfile.yml:15` — `YAMLFIX_IMAGE: otherguy/yamlfix:latest`. The `yaml-fix` task that used it was removed. Variable is unreferenced.
  - Fix: delete the line.

---

## Low

- [ ] **Pin Taskfile tool images to specific versions**
  - `Taskfile.yml` — `CSPELL_IMAGE`, `MARKDOWNLINT_IMAGE`, `KUBE_LINTER_IMAGE`, `PRETTIER_IMAGE` all use `:latest`.
  - Local `task all` is non-reproducible across time. Tool updates can silently break or change lint behavior.
  - Fix: pin each to a specific version tag. Add to Renovate `customManagers`.

- [ ] **Automate etcd backup**
  - No `talosctl etcd snapshot` task, CronJob, or documentation exists.
  - Single-node etcd: disk failure or bad Talos upgrade = unrecoverable cluster state.
  - Fix: add a Kubernetes CronJob or Talos machine config snippet that runs daily snapshots to the NAS.

---

## Planned Features

- [ ] Monitoring stack — Prometheus, Grafana, Loki
- [ ] cert-manager — TLS for Gateway API HTTPRoutes
- [ ] Authentik — SSO for all exposed apps
- [ ] Tailscale — remote LAN access without port forwarding
- [ ] ArgoCD notifications — Slack/email on sync failure
- [ ] Hubble UI via HTTPRoute (not just port-forward)
- [ ] Coral TPU integration
