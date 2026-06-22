# Homelab Backlog

Findings from June 2026 full-repo audit. Grouped by severity. Check off as completed.

---

## Critical — GitOps is broken or severely undermined

- [X] **Add `apps/.argocd/` — App of Apps is missing from git**
  - Create `apps/.argocd/root-application.yaml` (ArgoCD root Application pointing to `apps/.argocd/`)
  - Create `apps/.argocd/apps.yaml` (ApplicationSet with list generator, one entry per app)
  - Without these files ArgoCD has nothing to sync; GitOps is manual kubectl.
  - See CLAUDE.md "ArgoCD > App of Apps Pattern" for expected structure.

- [X] **Create `apps/core/external-secrets/` source files**
  - Directory exists with only a vendored chart. No `kustomization.yaml`, no manifests.
  - Needs: `kustomization.yaml` (helmChart for external-secrets), `namespace.yaml`, `ClusterSecretStore` for Bitwarden, and an `ExternalSecret` for `smb-creds`.

- [X] **Replace `smb-creds` kubectl comment with proper ExternalSecret**
  - `apps/core/storage/volumes.yaml:22-25` has a commented `kubectl create secret` as the only reference to `smb-creds`.
  - Move to `apps/core/external-secrets/smb-creds-external-secret.yaml` as an `ExternalSecret` backed by Bitwarden Secrets Manager.
  - Remove the comment from `volumes.yaml`.

- [X] **Remove redundant `cluster-admin` binding from ArgoCD**
  - `apps/core/argocd/namespace.yaml:101-117` — `argocd-controller-admin` ClusterRoleBinding grants `cluster-admin` on top of the already-broad custom ClusterRole.
  - Delete the `argocd-controller-admin` ClusterRoleBinding. The custom ClusterRole is sufficient.

- [X] **Fix CoreDNS ConfigMap conflict**
  - `apps/core/coredns-custom/configmap.yaml:16-51` defines a second full `coredns` ConfigMap as a resource (not a patch). ArgoCD will fail to create it — ConfigMap already exists.
  - Remove the second `coredns` ConfigMap entirely.
  - The first `coredns-custom` ConfigMap with the `.server` extension is correct for Talos. CoreDNS imports `custom/*.server` automatically.

---

## High — Correctness or reliability gaps

- [X] **Pin ArgoCD kustomization to specific version**
  - `apps/core/argocd/kustomization.yaml:8` uses `?ref=stable` (floating).
  - Changed to `?ref=v3.3.8`.

- [X] **Fix csi-driver-smb version mismatch**
  - `apps/core/storage/kustomization.yaml:12` declares `version: 1.19.1`.
  - Local vendored chart dir is `csi-driver-smb-1.20.1`.
  - Updated kustomization to `version: 1.20.1`.

- [X] **Pin filebrowser image**
  - `apps/media/filebrowser/deployment.yaml:17` — `hurlenko/filebrowser:latest`.
  - Pinned to `v2` with `imagePullPolicy: IfNotPresent`.

- [X] **Add health probes to filebrowser**
  - Added `livenessProbe` and `readinessProbe` on `/health` port 8080.

- [X] **Add SecurityContext to filebrowser**
  - Added `runAsNonRoot: true`, `allowPrivilegeEscalation: false`.

- [X] **Expose filebrowser externally**
  - Added `type: LoadBalancer` to `apps/media/filebrowser/service.yaml`.
  - Requires `CiliumLoadBalancerIPPool` + L2 policy — both added to `apps/core/cilium/`.

- [X] **Right-size filebrowser resources**
  - Changed to `requests: 256Mi/100m`, `limits: 1Gi/1000m`.

- [X] **Fix `autoupdate.yaml` branch name**
  - `.github/workflows/autoupdate.yaml:6` — changed `master` to `main`.

- [X] **Add `task build` / `task validate` step to CI**
  - Added `build-validate` job to `.github/workflows/linters.yaml` using `arduino/setup-task`.

- [X] **Fix or remove broken `yaml-fix` task**
  - Removed the `yaml-fix` task from `Taskfile.yml`; rely on `prettier` for YAML formatting.

---

## Medium — Missing config, outdated docs, best-practice gaps

- [X] **Add sync-wave annotations to all apps**
  - `apps/.argocd/apps.yaml` already uses `wave` field in list generator elements and templates to `argocd.argoproj.io/sync-wave` annotation.

- [X] **Add `CiliumLoadBalancerIPPool` and `CiliumL2AnnouncementPolicy` to git**
  - Added `apps/core/cilium/lb-ip-pool.yaml` and `apps/core/cilium/l2-announcement-policy.yaml`.
  - Added `l2announcements.enabled: true` and `externalIPs.enabled: true` to `apps/core/cilium/values.yaml`.

- [X] **Configure Renovate**
  - Created `.github/renovate.json` with schedules for Helm charts, container images, GitHub Actions, and Taskfile K8S_IMAGE.

- [X] **Bump `K8S_IMAGE` in Taskfile**
  - Updated `Taskfile.yml` from `alpine/k8s:1.31.13` to `alpine/k8s:1.36.3`.

- [X] **Add `CLAUDE.md` to git**
  - Created `CLAUDE.md` at repo root with full project context, conventions, wave table, resource defaults, and secrets pattern.

- [X] **Fix polaris task relative volume mount**
  - Changed `-v ".config:/config"` to `-v "{{.ROOT_DIR}}/.config:/config"`.

- [X] **Create ADR for External Secrets Operator + Bitwarden**
  - Created `docs/adrs/0005-external-secrets-bitwarden.md`.

- [X] **Create ADR for Cilium as CNI**
  - Created `docs/adrs/0006-cilium-cni.md`.

---

## Low — Cleanup and minor improvements

- [X] **Add explicit `replicas: 1` to filebrowser deployment**

- [X] **Add explicit `imagePullPolicy: IfNotPresent` to filebrowser** (after pinning tag)

- [X] **Update `bootstrap/cilium/README.md`** — updated version reference from `v1.18.0` to `1.19.3`.

- [X] **Populate `openspec/` or remove it** — directory was never tracked; no action needed.

- [X] **Add namespace-level `ResourceQuota`** — created `apps/media/filebrowser/resourcequota.yaml`.

- [X] **Add basic `NetworkPolicy`** — created `apps/media/filebrowser/networkpolicy.yaml` (egress: DNS + NAS 192.168.1.10:445).

---

## Planned Features (from TODO.md, not yet started)

- [ ] Monitoring stack — Prometheus, Grafana, Loki
- [ ] cert-manager — TLS for Gateway API HTTPRoutes
- [ ] Authentik — SSO for all exposed apps
- [ ] Tailscale — remote LAN access without port forwarding
- [ ] ArgoCD notifications — Slack/email on sync failure
- [ ] Hubble UI via HTTPRoute (not just port-forward)
- [ ] Coral TPU integration
