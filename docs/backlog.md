# Homelab Backlog

Findings from June 2026 full-repo audit. Grouped by severity. Check off as completed.

---

## Critical — GitOps is broken or severely undermined

- [X] **Add `apps/.argocd/` — App of Apps is missing from git**
  - Create `apps/.argocd/root-application.yaml` (ArgoCD root Application pointing to `apps/.argocd/`)
  - Create `apps/.argocd/apps.yaml` (ApplicationSet with list generator, one entry per app)
  - Without these files ArgoCD has nothing to sync; GitOps is manual kubectl.
  - See CLAUDE.md "ArgoCD > App of Apps Pattern" for expected structure.

- [ ] **Create `apps/core/external-secrets/` source files**
  - Directory exists with only a vendored chart. No `kustomization.yaml`, no manifests.
  - Needs: `kustomization.yaml` (helmChart for external-secrets), `namespace.yaml`, `ClusterSecretStore` for Bitwarden, and an `ExternalSecret` for `smb-creds`.

- [ ] **Replace `smb-creds` kubectl comment with proper ExternalSecret**
  - `apps/core/storage/volumes.yaml:22-25` has a commented `kubectl create secret` as the only reference to `smb-creds`.
  - Move to `apps/core/external-secrets/smb-creds-external-secret.yaml` as an `ExternalSecret` backed by Bitwarden Secrets Manager.
  - Remove the comment from `volumes.yaml`.

- [ ] **Remove redundant `cluster-admin` binding from ArgoCD**
  - `apps/core/argocd/namespace.yaml:101-117` — `argocd-controller-admin` ClusterRoleBinding grants `cluster-admin` on top of the already-broad custom ClusterRole.
  - Delete the `argocd-controller-admin` ClusterRoleBinding. The custom ClusterRole is sufficient.

- [ ] **Fix CoreDNS ConfigMap conflict**
  - `apps/core/coredns-custom/configmap.yaml:16-51` defines a second full `coredns` ConfigMap as a resource (not a patch). ArgoCD will fail to create it — ConfigMap already exists.
  - Remove the second `coredns` ConfigMap entirely.
  - The first `coredns-custom` ConfigMap with the `.server` extension is correct for Talos. CoreDNS imports `custom/*.server` automatically.

---

## High — Correctness or reliability gaps

- [ ] **Pin ArgoCD kustomization to specific version**
  - `apps/core/argocd/kustomization.yaml:8` uses `?ref=stable` (floating).
  - Change to a pinned tag, e.g. `?ref=v2.14.x`.

- [ ] **Fix csi-driver-smb version mismatch**
  - `apps/core/storage/kustomization.yaml:12` declares `version: 1.19.1`.
  - Local vendored chart dir is `csi-driver-smb-1.20.1`.
  - Update kustomization to `version: 1.20.1` (or clean chart dir to match).

- [ ] **Pin filebrowser image**
  - `apps/media/filebrowser/deployment.yaml:17` — `hurlenko/filebrowser:latest`.
  - Pin to a specific tag (e.g. `v2`) or image digest.

- [ ] **Add health probes to filebrowser**
  - No `livenessProbe` or `readinessProbe`.
  - Add both; filebrowser exposes `/health` on port 8080.

- [ ] **Add SecurityContext to filebrowser**
  - No `runAsNonRoot`, `readOnlyRootFilesystem`, or `allowPrivilegeEscalation: false`.
  - Minimum: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`.

- [ ] **Expose filebrowser externally**
  - `apps/media/filebrowser/service.yaml` defaults to `ClusterIP`. App is unreachable from LAN.
  - Add `type: LoadBalancer` to the service, or add an HTTPRoute via Cilium Gateway API.
  - Requires `CiliumLoadBalancerIPPool` + L2 policy to exist (see next item).

- [ ] **Right-size filebrowser resources**
  - Current: `requests: 1Gi/500m`, `limits: 4Gi/2000m`.
  - Per CLAUDE.md default: `requests: 256Mi/100m`, `limits: 1Gi/1000m`.
  - Adjust unless benchmarks justify higher values.

- [ ] **Fix `autoupdate.yaml` branch name**
  - `.github/workflows/autoupdate.yaml:6` targets `master`. Repo uses `main`.
  - Change to `branches: [main]`.

- [ ] **Add `task build` / `task validate` step to CI**
  - `.github/workflows/linters.yaml` only runs yamllint + markdownlint.
  - Add a job that runs `task build` and `task validate` so schema errors, kube-linter warnings, and polaris failures surface in CI.
  - Requires Docker available on runner (use `runs-on: ubuntu-latest` with Docker pre-installed).

- [ ] **Fix or remove broken `yaml-fix` task**
  - `Taskfile.yml:114` — comment documents that exclusions cause hangs and config is ignored.
  - Either fix the `yamlfix` invocation or remove the task and rely on `prettier` for YAML formatting.

---

## Medium — Missing config, outdated docs, best-practice gaps

- [ ] **Add sync-wave annotations to all apps**
  - No app has `argocd.argoproj.io/sync-wave`. Resources race at sync time.
  - Per CLAUDE.md wave table: namespaces → -2, secrets/ESO → -1, Cilium/ArgoCD → 0, CSI drivers → 1, Gateway → 2, monitoring → 3, workloads → 4+.

- [ ] **Add `CiliumLoadBalancerIPPool` and `CiliumL2AnnouncementPolicy` to git**
  - Referenced in CLAUDE.md but not in `apps/core/cilium/`.
  - Without these, Cilium LB-IPAM can't assign IPs to `LoadBalancer` services.

- [ ] **Configure Renovate**
  - CLAUDE.md says "Renovate bot creates incremental PRs" but no `.github/renovate.json` exists.
  - Create `renovate.json` with schedules for Helm chart versions, container image tags, Talos/K8s version bumps, and GitHub Actions pinning.

- [ ] **Bump `K8S_IMAGE` in Taskfile**
  - `Taskfile.yml:21` — `alpine/k8s:1.31.13`. Cluster runs kubelet `1.36`.
  - Update to `alpine/k8s:1.36.x` to match cluster version.

- [ ] **Add `CLAUDE.md` to git**
  - Project instructions file referenced throughout tooling doesn't exist on disk.
  - `.cursorrules` mirrors it but isn't the authoritative source for Claude tooling.
  - Create `CLAUDE.md` at repo root (can sync content from `.cursorrules`).

- [ ] **Fix polaris task relative volume mount**
  - `Taskfile.yml:255` — `-v ".config:/config"` uses relative path.
  - Change to `-v "{{.ROOT_DIR}}/.config:/config"` for reliability.

- [ ] **Create ADR for External Secrets Operator + Bitwarden**
  - No ADR documents the ESO + BSM decision. Add `docs/adrs/0005-external-secrets-bitwarden.md`.

- [ ] **Create ADR for Cilium as CNI**
  - No ADR for Cilium. Add `docs/adrs/0006-cilium-cni.md`.

---

## Low — Cleanup and minor improvements

- [ ] **Add explicit `replicas: 1` to filebrowser deployment**

- [ ] **Add explicit `imagePullPolicy: IfNotPresent` to filebrowser** (after pinning tag)

- [ ] **Update `bootstrap/cilium/README.md`** — references `v1.18.0`, actual deployed version is `1.19.3`.

- [ ] **Populate `openspec/` or remove it** — directories exist with no tracked content.

- [ ] **Add namespace-level `ResourceQuota`** for `filebrowser` and future media namespaces.

- [ ] **Add basic `NetworkPolicy`** for filebrowser — deny all egress except to NAS (`192.168.1.10:445`) and DNS.

---

## Planned Features (from TODO.md, not yet started)

- [ ] Monitoring stack — Prometheus, Grafana, Loki
- [ ] cert-manager — TLS for Gateway API HTTPRoutes
- [ ] Authentik — SSO for all exposed apps
- [ ] Tailscale — remote LAN access without port forwarding
- [ ] ArgoCD notifications — Slack/email on sync failure
- [ ] Hubble UI via HTTPRoute (not just port-forward)
- [ ] Coral TPU integration
