# Homelab Backlog

Findings from security + architecture audit. Grouped by severity.

---

## Critical

- [ ] **Enable TLS on Bitwarden SDK server**
  - `apps/core/external-secrets/values.yaml` — `bitwarden-sdk-server.image.tls.enabled: false`.
  - Any pod can hit `http://bitwarden-sdk-server.external-secrets.svc.cluster.local:9998` in plaintext.
  - Requires cert-manager (planned) to provision a cert, or manual cert injection.
  - Fix: deploy cert-manager first, then set `tls.enabled: true` and update `ClusterSecretStore` URL to `https://`.

- [ ] **Replace placeholder UUIDs in smb-creds ExternalSecret**
  - `apps/core/external-secrets/smb-creds.yaml` — `key: "<REPLACE-WITH-BSM-UUID-FOR-SMB-USERNAME>"`.
  - ESO fails to sync every hour. `smb-creds` Secret never materializes. PVC mount fails. Storage is broken.
  - Fix: create two items in Bitwarden Secrets Manager (SMB username, SMB password). Replace both UUID placeholders with the real BSM item IDs. The items should be named `smb/username` and `smb/password` under the homelab project for discoverability.

---

## High

- [X] **Pin Cilium Helm chart version** — `apps/core/cilium/kustomization.yaml`, pinned to `1.19.3`.

- [X] **Remove RBAC write escalation from ArgoCD ClusterRole** — `clusterroles`/`clusterrolebindings` now read-only in `apps/core/argocd/namespace.yaml`.

- [X] **Add NetworkPolicy to external-secrets + core-secrets namespaces** — `apps/core/external-secrets/networkpolicy.yaml` created; denies cross-namespace ingress.

- [X] **Add StorageClass `photos-pv` to git** — `apps/core/storage/storageclass.yaml` created.

- [ ] **Add persistent `/config` volume to filebrowser**
  - `apps/media/filebrowser/deployment.yaml` — only mounts `/data` (read-only). No `/config` mount.
  - filebrowser database (users, settings) is on the ephemeral layer and wiped on every pod restart.
  - Requires an SMB share on the NAS (e.g., `//asgard.local/appdata/filebrowser`). Create share first, then:
    - Add PV + PVC for the config share (ReadWriteMany or RWO).
    - Mount at `/config` in the Deployment.
    - Add `--database /config/filebrowser.db` to container args.

- [X] **Add ingress NetworkPolicy + restrict LoadBalancer source** — `apps/media/filebrowser/networkpolicy.yaml` now includes Ingress from `192.168.1.0/24`; `service.yaml` has `loadBalancerSourceRanges`.

- [X] **Gate PR merges on CI** — `.github/workflows/linters.yaml` now triggers on `pull_request` as well as `push`. Enable branch protection on `main` in GitHub settings (required status checks, no direct push).

- [X] **Fix Taskfile validation tasks swallowing exit codes** — all `||` silent-failure fallbacks replaced with `|| { ... exit 1; }`.

- [X] **Add CRD schema sources to kubeconform, remove `-ignore-missing-schemas`** — `Taskfile.yml` validate-schema task now includes the CRDs catalog and fails on unknown schemas.

- [ ] **Pin GitHub Actions to commit SHAs**
  - `.github/workflows/linters.yaml` — all actions use mutable version tags (`@v5`, `@v3`, etc.).
  - Renovate (already configured with `github-actions` group) will handle this automatically once installed and authorized in the repo.

- [X] **Prune polaris.yaml** — removed ~150 lines of AWS/Datadog/kops exemptions. Now contains only exemptions for components that actually run in this cluster.

---

## Medium

- [X] **Add deny-cross-namespace-ingress NetworkPolicy to core-argocd** — `apps/core/argocd/networkpolicy.yaml` created.

- [ ] **Configure ArgoCD OIDC/SSO**
  - `apps/core/argocd/argocd-cm.yaml` — no OIDC config. All users share `admin` account.
  - Fix short-term: set strong `admin` password via bootstrapped Secret.
  - Fix long-term: deploy Authentik (planned feature) and configure Dex OIDC in ArgoCD.

- [X] **Add `runAsUser: 1000` to filebrowser** — `apps/media/filebrowser/deployment.yaml` securityContext updated.

- [X] **Set `strategy: Recreate` on filebrowser Deployment** — explicit, honest for single-replica.

- [X] **Remove dead `YAMLFIX_IMAGE` variable from Taskfile**.

- [X] **Delete orphaned ArgoCD vendored chart** — `apps/core/argocd/charts/` is gitignored (not tracked); no action needed.

---

## Low

- [ ] **Pin Taskfile tool images to specific versions**
  - `CSPELL_IMAGE`, `MARKDOWNLINT_IMAGE`, `KUBE_LINTER_IMAGE`, `PRETTIER_IMAGE` all use `:latest`.
  - Check current versions via `docker pull && docker inspect`, pin, then add to Renovate `customManagers`.

- [ ] **Automate etcd backup**
  - No snapshot task exists. Single-node etcd loss = full cluster rebuild.
  - Fix: add a CronJob or Talos machine config task that runs `talosctl etcd snapshot` daily and uploads to NAS.

---

## Planned Features

- [ ] Monitoring stack — Prometheus, Grafana, Loki
- [ ] cert-manager — TLS for Gateway API HTTPRoutes (also unblocks Bitwarden SDK TLS)
- [ ] Authentik — SSO for all exposed apps (also unblocks ArgoCD OIDC)
- [ ] Tailscale — remote LAN access without port forwarding
- [ ] ArgoCD notifications — Slack/email on sync failure
- [ ] Hubble UI via HTTPRoute (not just port-forward)
- [ ] Coral TPU integration
