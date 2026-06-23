# Homelab Backlog

Findings from security + architecture audit. Grouped by severity.

---

## Critical

- [ ] **Enable TLS on Bitwarden SDK server**
  - `apps/core/external-secrets/values.yaml` — `bitwarden-sdk-server.image.tls.enabled: false`.
  - Any pod can hit `http://bitwarden-sdk-server.external-secrets.svc.cluster.local:9998` in plaintext. All Bitwarden-backed secrets transit unencrypted intra-cluster.
  - Fix: deploy cert-manager first, then set `tls.enabled: true` and update `ClusterSecretStore` URL to `https://`. Alternatively enable Cilium WireGuard transparent encryption as a network-layer fix.

- [ ] **Replace placeholder UUIDs in smb-creds ExternalSecret**
  - `apps/core/external-secrets/smb-creds.yaml` — `key: "<REPLACE-WITH-BSM-UUID-FOR-SMB-USERNAME>"`.
  - ESO fails to sync. `smb-creds` Secret never materializes. PVC mount fails. Storage is broken on a fresh deploy.
  - Fix: create two items in Bitwarden Secrets Manager (SMB username, SMB password). Replace both UUID placeholders with the real BSM item IDs.

- [ ] **Create ArgoCD AppProject with source/destination restrictions**
  - All Applications run in the `default` project. No `AppProject` exists. Zero source repo, destination namespace, or cluster resource restrictions.
  - A compromised or malicious Helm chart in any synced Application can deploy to any namespace or create cluster-scoped resources.
  - Fix: create an `AppProject` named `homelab` with `sourceRepos: ["https://github.com/mkoelle/homelab"]`, explicit `destinations` (known namespaces only), and a scoped `clusterResourceWhitelist`. Bind all Applications to it.

- [ ] **Remove auto-prune from root Application; add sync safety gate for core apps**
  - `apps/.argocd/root-application.yaml` — `prune: true` + `selfHeal: true`. `apps/.argocd/apps.yaml` — same on all apps including wave -1 and wave 0.
  - A single bad push to `main` deletes live cluster resources including PVs, Secrets, and RBAC. If ArgoCD deletes itself, it cannot self-recover.
  - Fix: remove `prune: true` from `root-application.yaml`. For wave -1/0 apps (external-secrets, argocd, cilium), remove automated sync entirely and require manual ArgoCD sync. Add Sync Windows to prevent automated syncs during off-hours.

---

## High

- [ ] **Scope ArgoCD application-controller ClusterRole (remove wildcard secret read)**
  - `apps/core/argocd/kustomization.yaml:25` — `apiGroups: ["*"] resources: ["*"] verbs: [get, list, watch]` grants read on ALL resources cluster-wide, including Secrets in every namespace.
  - Compromised application-controller = full secret exfiltration across the entire cluster.
  - Fix: replace the wildcard read rule with explicit API group + resource pairs. Exclude `""` group `secrets` from the read rule. Add `resourceExclusions` in `argocd-cm` to prevent ArgoCD from syncing raw Secrets.

- [ ] **Pin filebrowser image to digest**
  - `apps/media/filebrowser/deployment.yaml:27` — `image: hurlenko/filebrowser:v2` is a floating major version tag.
  - Any silent update to the `v2` tag on Docker Hub deploys arbitrary code on next pod restart.
  - Fix: pin to `hurlenko/filebrowser:v2@sha256:<digest>`. Consider switching to `filebrowser/filebrowser` (official upstream). Configure Renovate `containerDigest` preset.

- [ ] **Add egress NetworkPolicy to core-argocd and external-secrets namespaces**
  - Both namespaces have ingress-only NetworkPolicies (`policyTypes: [Ingress]`). No egress restrictions.
  - Compromised ArgoCD or ESO can reach any pod in the cluster, any external endpoint, or the Talos API (port 50000).
  - Fix: add explicit egress policies. `core-argocd`: allow GitHub (443), cluster DNS (53), kube-apiserver (6443), Redis (6379), Dex (5556) — deny all else. `external-secrets`: allow bitwarden-sdk-server (9998), Bitwarden API (443), cluster DNS (53), kube-apiserver (6443) — deny all else.

- [ ] **Add container image CVE scanning to CI (Trivy)**
  - CI pipeline runs yamllint → kustomize build → kubeconform → kube-linter → polaris. No image scanning.
  - Vulnerable base images run until a human notices or Renovate bumps the tag.
  - Fix: add Trivy step after `kustomize build` to scan manifests for image references and check for CRITICAL/HIGH CVEs. Fail CI on CRITICAL findings.

- [ ] **Scope kube-linter global security exclusions**
  - `.config/kube-linter.yaml` globally excludes `run-as-non-root`, `no-read-only-root-fs`, `privilege-escalation-container`, `privileged-container` for every workload in every namespace.
  - CI reports green while meaningful security checks are silently bypassed. Any new app inherits these suppressions.
  - Fix: remove global exclusions. Scope per-object via kube-linter annotations (`kube-linter.io/ignore-check`) on specific vendor resources that legitimately need exceptions.

- [ ] **Enforce PodSecurity `restricted` for user workload namespaces**
  - `bootstrap/talos/controlplane.yaml:264` — global default enforces `baseline`, only warns/audits `restricted`.
  - Workload namespaces can deploy containers without seccomp profiles, with writable root filesystems, or with capabilities, and admission will not reject them.
  - Fix: add per-namespace labels to user app namespaces (e.g., `filebrowser`):
    ```yaml
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    ```
  - Vendor namespaces (kube-system, core-argocd, external-secrets) retain `baseline` enforcement.

- [ ] **Deploy observability stack: Prometheus + Grafana + Loki + Alertmanager**
  - Zero metrics, logs, alerting, or tracing. Hubble provides CNI-level flows with no persistence or alerting.
  - Silent failures go undetected. CrashLoopBackOff, OOM kills, storage saturation, ArgoCD OutOfSync — all invisible until manually checked.
  - Fix: deploy `kube-prometheus-stack` (wave 3), enable Cilium Prometheus integration, deploy Loki + Promtail. Set minimum alerts: pod CrashLoop, node memory >80%, etcd latency, ArgoCD OutOfSync >10min.

- [ ] **Add persistent `/config` volume to filebrowser**
  - `apps/media/filebrowser/deployment.yaml` — only mounts `/data` (read-only NAS share). No `/config` mount.
  - filebrowser database (users, settings) is on the ephemeral container layer and wiped on every pod restart or image update.
  - Fix: create an SMB share on the NAS (`//asgard.local/appdata/filebrowser`), add PV + PVC (ReadWriteOnce), mount at `/config` in the Deployment, add `--database /config/filebrowser.db` to container args.

- [ ] **Pin GitHub Actions to commit SHAs**
  - `.github/workflows/linters.yaml` — all actions use mutable version tags (`@v5`, `@v3`, etc.).
  - Renovate (configured with `github-actions` group) will handle this automatically once authorized in the repo settings.

---

## Medium

- [ ] **Add default-deny NetworkPolicy for kube-system**
  - No NetworkPolicy covers `kube-system`. All pods there can freely reach any pod in any namespace.
  - CSI driver or CNI vulnerability → lateral movement to external-secrets (Bitwarden token) and filebrowser.
  - Fix: add default-deny-ingress for `kube-system` with explicit allow rules for CoreDNS (port 53 from all namespaces), Cilium health checks (port 4240), and kubelet→CSI controller flows.

- [ ] **Vendor ArgoCD upstream manifests (remove live GitHub fetch)**
  - `apps/core/argocd/kustomization.yaml:9` — `github.com/argoproj/argo-cd//manifests/cluster-install?ref=v3.3.8` fetches live from GitHub at every `kustomize build`.
  - Build fails if GitHub is unavailable. Supply chain risk if the upstream ref is tampered with. `.build` directories are gitignored so artifacts are not pinned.
  - Fix: vendor the manifests locally (like cilium and external-secrets charts). Run `task build` pointing to local files only. Renovate can track the `ref=` string to automate version bumps.

- [ ] **Add CI validation for placeholder UUID detection**
  - `apps/core/external-secrets/smb-creds.yaml` contains `<REPLACE-WITH-BSM-UUID-...>` placeholders that pass all CI checks.
  - A fresh cluster deploy with unsubstituted placeholders fails silently at runtime, not at CI time.
  - Fix: add a pre-build grep step to CI:
    ```bash
    grep -rq "REPLACE-WITH" apps/ && echo "ERROR: placeholder UUIDs found" && exit 1
    ```

- [ ] **Configure ArgoCD OIDC/SSO and RBAC policy**
  - `apps/core/argocd/argocd-cm.yaml` — no OIDC config. No `argocd-rbac-cm` exists. Default RBAC grants anonymous read access to all Applications.
  - Fix short-term: set `policy.default: role:''` in `argocd-rbac-cm` (deny by default) and a named admin policy. Set strong `admin` password via bootstrapped Secret.
  - Fix long-term: deploy Authentik (planned) and configure Dex OIDC in ArgoCD.

- [ ] **Configure filebrowser credentials and TLS**
  - `apps/media/filebrowser/service.yaml` — exposes HTTP port 80 to `192.168.1.0/24`. Default filebrowser credentials are `admin/admin`.
  - Any LAN device (IoT, guest WiFi on same subnet) has potential unauthenticated access to the photo library over cleartext HTTP.
  - Fix: mount `filebrowser.json` settings from a Secret (via ExternalSecret) with a non-default admin password. Add TLS via Gateway API + cert-manager once both are deployed.

- [ ] **Pin Taskfile tool images to specific versions**
  - `Taskfile.yml` — `CSPELL_IMAGE`, `MARKDOWNLINT_IMAGE`, `KUBE_LINTER_IMAGE`, `PRETTIER_IMAGE` use `:latest`; `PLUTO_IMAGE` uses `:v5`; `POLARIS_IMAGE` uses `:10`.
  - CI results are non-reproducible. A compromised `:latest` image silently subverts CI.
  - Fix: pin all to digests. Add custom Renovate managers for each `IMAGE_VAR: image:tag` pattern in `Taskfile.yml`.

- [ ] **Automate etcd backup**
  - No snapshot task exists. Single-node etcd loss = full cluster rebuild.
  - Fix: add a CronJob or Talos machine config that runs `talosctl etcd snapshot` daily and uploads to the NAS. Store `controlplane.yaml` and `talosconfig` in Bitwarden (recovery requires them; local filesystem only = disk failure = permanent cluster lockout).

---

## Low

- [ ] **Upgrade audit logging to RequestResponse for Secrets access**
  - `bootstrap/talos/controlplane.yaml:276` — global `level: Metadata`. Request/response bodies not logged.
  - Secret exfiltration (`GET /api/v1/namespaces/.../secrets/...`) logs the access but not the content. Post-incident forensics cannot prove data exposure.
  - Fix: once log storage exists (Loki), add a `RequestResponse` rule scoped to `resources: ["secrets"]` before the catch-all `Metadata` rule.

- [ ] **Disable Gateway API or deploy GatewayClass + Gateway with policies**
  - `apps/core/cilium/values.yaml:42` — `gatewayAPI.enabled: true` with ALPN + appProtocol enabled. No `GatewayClass`, `Gateway`, or `HTTPRoute` exists in the repo.
  - Unused enabled infrastructure. Any accidental `Gateway` object would expose internal services with no pre-existing policy to block it.
  - Fix: either disable `gatewayAPI.enabled: false` until ready to use, or deploy a `GatewayClass` + `Gateway` with proper HTTPRoutes and TLS (unblocks cert-manager + Hubble UI items).

---

## Planned Features

- [ ] cert-manager — TLS for Gateway API HTTPRoutes (also unblocks Bitwarden SDK TLS)
- [ ] Authentik — SSO for all exposed apps (also unblocks ArgoCD OIDC)
- [ ] Tailscale — remote LAN access without port forwarding
- [ ] ArgoCD notifications — Slack/email on sync failure
- [ ] Hubble UI via HTTPRoute (not just port-forward)
- [ ] Coral TPU integration
