# Homelab Backlog

Findings from security + architecture audit. Grouped by severity.

---

## Critical

- [ ] **Enable TLS on Bitwarden SDK server**
  - `apps/core/external-secrets/values.yaml` — `bitwarden-sdk-server.image.tls.enabled: false`.
  - Any pod can reach `http://bitwarden-sdk-server.external-secrets.svc.cluster.local:9998` in plaintext. All Bitwarden-backed secrets transit unencrypted intra-cluster.
  - Fix (immediate): enable Cilium WireGuard transparent encryption (`encryption.enabled: true, encryption.type: wireguard` in Cilium values) — encrypts all pod-to-pod traffic without cert-manager dependency.
  - Fix (long-term): deploy cert-manager, set `tls.enabled: true`, update `ClusterSecretStore` URL to `https://`.

- [ ] **Replace placeholder UUIDs in smb-creds ExternalSecret**
  - `apps/core/external-secrets/smb-creds.yaml` — `key: "<REPLACE-WITH-BSM-UUID-FOR-SMB-USERNAME>"`.
  - ESO fails to sync. `smb-creds` Secret never materializes. PVC mount fails. Storage broken on fresh deploy.
  - Fix: create two items in Bitwarden Secrets Manager (SMB username, SMB password). Replace both UUID placeholders with real BSM item IDs.

- [x] **ArgoCD root-application uses `project: default`, bypassing AppProject**
  - `apps/.argocd/root-application.yaml:6` — `project: default`. AppProject `homelab` restricts source repos, destination namespaces, and cluster resource types — but the root Application is not bound to it. The most privileged object in the cluster is ungated.
  - Fix: change `project: default` → `project: homelab`. The AppProject already has `argoproj.io/Application` in `clusterResourceWhitelist`.

- [x] **Trivy misconfiguration scan never fails CI**
  - `.github/workflows/linters.yaml` — `exit-code: "0"`. Trivy runs on every PR but never blocks a merge regardless of CRITICAL/HIGH findings. Security scan is decorative.
  - Fix: set `exit-code: "1"`. Add `.trivyignore` to suppress known vendor exceptions (Cilium, CSI driver) rather than globally silencing the gate.

---

## High

- [x] **ArgoCD ClusterRole still has API group wildcards**
  - `apps/core/argocd/kustomization.yaml` — `cilium.io: resources: ["*"]`, `external-secrets.io: resources: ["*"]`, `gateway.networking.k8s.io: resources: ["*"]`. A compromised application-controller can reconfigure `ClusterSecretStore` (re-point Bitwarden backend), manipulate `CiliumNetworkPolicy`, or create arbitrary Gateway resources.
  - Fix: replace wildcards with explicit resource lists. `cilium.io`: only `ciliuml2announcementpolicies`, `ciliumloadbalancerippools`. `external-secrets.io`: only `externalsecrets`, `clustersecretstores`. `gateway.networking.k8s.io`: only include if Gateway API is actively used.

- [x] **Autoupdate GitHub Action uses unpinned third-party Docker image**
  - `.github/workflows/autoupdate.yaml` — `docker://chinthakagodawita/autoupdate-action:v1`. Mutable tag, third-party image, runs on every `main` merge with full `GITHUB_TOKEN`. Tag can be silently overwritten with malicious code.
  - Fix: pin to a commit SHA digest, switch to a maintained alternative with SHA pin, or remove (Renovate handles PR rebasing natively).

- [x] **Renovate github-actions group has `automerge: true`**
  - `.github/renovate.json` — github-actions updates auto-merge when CI passes. Combined with the unpinned autoupdate action running on every main merge, a malicious Renovate PR that updates an action to a compromised SHA would auto-merge and execute with repo write access.
  - Fix: remove `automerge: true` from the github-actions package rule. Require human approval. Or restrict to SHA-only bumps.

- [ ] **Automate etcd backup**
  - No snapshot exists. Single-node etcd loss = full cluster rebuild. `controlplane.yaml` and `talosconfig` on local disk only — disk failure also destroys bootstrap credentials needed to rebuild.
  - Fix: add a CronJob (wave 3, kube-system) running `talosctl etcd snapshot` daily, uploading to `//asgard.local/backups/etcd/`. Store `controlplane.yaml` and `talosconfig` in Bitwarden.

- [ ] **Filebrowser serves HTTP with default `admin/admin` credentials**
  - `apps/media/filebrowser/service.yaml` — `type: LoadBalancer, port: 80` to `192.168.1.0/24`. No `filebrowser.json` Secret mount. Default credentials are `admin`/`admin`. Any LAN device can authenticate and read the photo library.
  - Fix (immediate): mount `filebrowser.json` from a Secret (via ExternalSecret) with bcrypt-hashed non-default admin password. Takes one ExternalSecret + ConfigMap mount.
  - Fix (long-term): TLS via Gateway API + cert-manager once both are deployed.

- [ ] **Scope kube-linter global security exclusions**
  - `.config/kube-linter.yaml` — globally excludes `run-as-non-root`, `no-read-only-root-fs`, `privilege-escalation-container`, `privileged-container` for every workload in every namespace. New apps inherit suppressions silently; CI reports green.
  - Fix: remove global exclusions. Use per-object annotations (`kube-linter.io/ignore-check`) on vendor resources that legitimately need exceptions.

- [ ] **Deploy observability stack: Prometheus + Grafana + Loki + Alertmanager**
  - Zero metrics, logs, alerting, or tracing. Hubble has no persistence or alerting. Silent failures: CrashLoopBackOff, OOM kills, storage saturation, ArgoCD OutOfSync — all invisible until manually checked.
  - Fix: deploy `kube-prometheus-stack` (wave 3), enable Cilium Prometheus integration, deploy Loki + Promtail. Minimum alerts: pod CrashLoop, node memory >80%, etcd latency, ArgoCD OutOfSync >10min.

---

## Medium

- [x] **filebrowser data volumeMount missing `readOnly: true`**
  - `apps/media/filebrowser/deployment.yaml` — PVC is `ReadOnlyMany` but `volumeMount` has no `readOnly: true`. CSI bug or storageClass change removes the only guard.
  - Fix: add `readOnly: true` to the `data` volumeMount.

- [ ] **Add persistent `/config` volume to filebrowser**
  - `apps/media/filebrowser/deployment.yaml` — no `/config` mount. filebrowser database (users, settings, credentials configured at runtime) is on the ephemeral container layer and wiped on every pod restart or image update.
  - Fix: create SMB share on NAS (`//asgard.local/appdata/filebrowser`), add PV + PVC (ReadWriteOnce), mount at `/config`, add `--database /config/filebrowser.db` to container args.

- [x] **Configure ArgoCD RBAC policy (deny-by-default)**
  - No `argocd-rbac-cm` exists. Default RBAC grants anonymous read access to all Applications. Any user who can reach the ArgoCD server (or port-forward) can enumerate all Applications and observe sync state.
  - Fix (immediate): add `argocd-rbac-cm` with `policy.default: role:''` (deny all) and explicit admin policy. Set strong ArgoCD admin password from a Secret.
  - Fix (long-term): deploy Authentik, configure Dex OIDC in ArgoCD.

- [ ] **Add default-deny NetworkPolicy for kube-system**
  - No NetworkPolicy covers `kube-system`. All pods there can freely reach any pod in any namespace. CSI driver or CNI vulnerability → lateral movement to external-secrets (Bitwarden token) and filebrowser.
  - Fix: add default-deny-ingress for `kube-system` with explicit allow rules for CoreDNS (port 53 from all namespaces), Cilium health checks (port 4240), kubelet→CSI controller flows.

- [ ] **Vendor ArgoCD upstream manifests (remove live GitHub fetch)**
  - `apps/core/argocd/kustomization.yaml` — `github.com/argoproj/argo-cd//manifests/cluster-install?ref=v3.3.8` fetches live from GitHub at every `kustomize build`. Build fails if GitHub is unavailable. Supply chain risk if upstream ref is tampered with.
  - Fix: vendor manifests locally (like cilium and ESO charts). Renovate already tracks the `ref=` string via custom manager.

- [x] **Add Renovate custom managers for all Taskfile tool images**
  - `.github/renovate.json` — only `K8S_IMAGE` is tracked. `CSPELL_IMAGE`, `MARKDOWNLINT_IMAGE`, `KUBE_LINTER_IMAGE`, `PLUTO_IMAGE`, `POLARIS_IMAGE`, `PRETTIER_IMAGE` accumulate CVEs silently.
  - Fix: add generic regex custom manager matching `_IMAGE: image:tag` pattern in `Taskfile.yml`.

- [x] **Deploy GatewayClass + Gateway or disable Gateway API**
  - `apps/core/cilium/values.yaml` — `gatewayAPI.enabled: true` with ALPN and appProtocol. No `GatewayClass`, `Gateway`, or `HTTPRoute` exists. An accidental Gateway object would expose internal services with no pre-existing policy.
  - Fix: disable `gatewayAPI.enabled: false` until cert-manager is deployed, or deploy a `GatewayClass` + `Gateway` now so future HTTPRoute objects require explicit opt-in.

---

## Low

- [x] **Disable `externalIPs.enabled` in Cilium**
  - `apps/core/cilium/values.yaml` — `externalIPs.enabled: true`. No ExternalIP objects deployed. A malicious Service spec with `externalIPs: [192.168.1.x]` bypasses `loadBalancerSourceRanges` restrictions protecting filebrowser.
  - Fix: set `externalIPs.enabled: false` unless a specific use case requires it.

- [ ] **Upgrade audit logging to RequestResponse for Secrets access**
  - `bootstrap/talos/controlplane.yaml` — global `level: Metadata`. Secret exfiltration via `GET .../secrets/...` logs the access but not the content. Post-incident forensics cannot confirm data exposure.
  - Fix: once Loki is deployed, prepend a `RequestResponse` rule scoped to `resources: ["secrets"]` before the global Metadata rule.

---

## Planned Features

- [ ] cert-manager — TLS for Gateway API HTTPRoutes (unblocks Bitwarden SDK TLS and filebrowser HTTPS)
- [ ] Authentik — SSO for all exposed apps (unblocks ArgoCD OIDC)
- [ ] Tailscale — remote LAN access without port forwarding
- [ ] ArgoCD notifications — Slack/email on sync failure
- [ ] Hubble UI via HTTPRoute (not just port-forward)
- [ ] Coral TPU integration
