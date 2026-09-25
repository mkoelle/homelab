# Project Context

This is a Kubernetes Homelab repository managed via GitOps (Argo CD).
The infrastructure is built on Talos Linux and uses Cilium for networking.

## Tech Stack

- **Orchestration**: Kubernetes (Talos)
- **GitOps**: Argo CD (App of Apps pattern)
- **Manifest Management**: Kustomize + Helm Charts (Hybrid)
- **Automation**: Taskfile (go-task)
- **Networking**: Cilium (L2 announcements via ARP — no BGP, home router lacks BGP support)
- **Secrets**: External Secrets Operator + Bitwarden Secrets Manager

## Hardware

| Host              | IP                | Role                          |
| ----------------- | ----------------- | ----------------------------- |
| `motherbox.local` | 192.168.1.2       | Kubernetes node (single-node) |
| `asgard.local`    | 192.168.1.10      | Synology NAS (SMB storage)    |
| LB pool           | 192.168.1.200–254 | Cilium LoadBalancer IPs       |

## Project Structure

- `apps/<category>/<app_name>`: Application manifests.
  - Each app should have a `kustomization.yaml`, `namespace.yaml`, and `values.yaml`.
  - Use `helmCharts` in `kustomization.yaml` to inflate charts.
- `apps/.argocd/`: Contains the "App of Apps" bootstrap configuration.
  - `apps/.argocd/apps.yaml`: ApplicationSet that manages all applications via list generator.
  - `apps/.argocd/root-application.yaml`: Bootstrap manifest to initialize the App of Apps.
- `apps/core/`: Platform-level apps (ArgoCD, Cilium, storage, external-secrets).
- `apps/media/`: User workloads (filebrowser, etc.).
- `Taskfile.yml`: Source of truth for build and verification commands (Docker-based).

## Development Conventions

### 1. Adding a New Application

- Create a directory: `apps/<category>/<app_name>`.
- Create `namespace.yaml` with the app namespace.
- Create `values.yaml` — only override what is necessary. Disable persistence by default.
- Create `kustomization.yaml`:
  - Set `namespace: <app_name>`.
  - Include `resources: [namespace.yaml]`.
  - Define `helmCharts` block pointing to the upstream repo.
- Add an entry to the `elements` list in `apps/.argocd/apps.yaml` with `name`, `path`, `namespace`, and `wave`.

### 2. Verification

- ALWAYS run `task build` to verify Kustomize builds and Helm template inflation.
- Run `task validate` for schema checks, kube-linter, and polaris audits.
- Fix any linting errors or missing Helm repos immediately.

### 3. App of Apps Pattern

- The root application is `apps/.argocd/root-application.yaml`.
- It syncs `apps/.argocd/`, which contains an `ApplicationSet`.
- The `ApplicationSet` uses a list generator — one `Application` per element.
- Cilium has a dedicated `apps/.argocd/cilium-application.yaml` (not in the list generator).

### 4. ArgoCD Sync Waves

Add `argocd.argoproj.io/sync-wave` to Application objects (via the `wave` field in `apps/.argocd/apps.yaml` elements) to control sync ordering:

| Wave | Layer                         |
| ---- | ----------------------------- |
| -2   | Namespaces                    |
| -1   | Secrets / ESO                 |
| 0    | Cilium / ArgoCD (core GitOps) |
| 1    | CSI drivers                   |
| 2    | Gateway API / routing         |
| 3    | Monitoring                    |
| 4+   | User workloads                |

Within a single app, resources can carry their own `argocd.argoproj.io/sync-wave` annotation too, for ordering *inside* that app (independent of the app-level wave above). Prefer this over Helm hooks (`helm.sh/hook`) for ordering resources a vendored chart ships as pre-install/pre-upgrade hooks: Argo CD treats those as PreSync hooks, which block the *entire* Sync phase — including every other normal resource in the app, regardless of its own sync-wave — until the hook succeeds. If that hook resource (e.g. a DB-init Job) itself depends on another resource in the same app (e.g. a bundled StatefulSet database) that only gets created in the Sync phase, that's a hard deadlock: the hook waits on something Argo won't create until the hook succeeds. This bit `apps/core/zitadel` (init/setup Jobs vs. the bundled Postgres StatefulSet) — fixed by stripping the chart's `helm.sh/hook*` annotations via a kustomize patch (`apps/core/zitadel/patch-chart-jobs.yaml`) and re-sequencing with plain `sync-wave` instead, so ordinary wave-boundary health-gating (Argo already waits for a wave's resources, Jobs and StatefulSets included, to go Healthy before starting the next wave) does the job. Only keep a chart's hook annotations for resources whose dependencies live *outside* the app entirely (nothing in-app they'd block on), or for genuine lifecycle-only hooks like `post-delete` (only fires on Application deletion, never gates a normal Sync). One more consequence of demoting a one-shot Job this way: don't give it `ttlSecondsAfterFinished`. With `selfHeal: true`, a completed Job that TTL-cleans itself away reads as "missing" on the next drift check and gets silently recreated — and a recreated Job re-runs its pod from scratch, so a one-shot DB-init Job would keep re-executing forever, roughly every resync. Let it persist (no TTL) so it stays Synced+Healthy with nothing left to reconcile; a real re-run is a manual `kubectl delete job`.

### 5. Secrets Pattern

- Secrets come from **Bitwarden Secrets Manager** via External Secrets Operator.
- `ClusterSecretStore` is defined in `apps/core/external-secrets/cluster-secret-store.yaml`.
- Each consuming app creates an `ExternalSecret` that references the store.
- Materialized secrets land in `core-secrets` namespace.
- Never commit raw secrets. Replace UUIDs in ExternalSecret remoteRef.key with real BSM IDs before applying.

### 6. Networking

- Cilium uses **L2 announcements** (ARP) for LoadBalancer IPs. Never configure BGP — home router has no BGP support.
- LB IP pool: `192.168.1.200–192.168.1.254` (see `apps/core/cilium/lb-ip-pool.yaml`).
- L2 policy: `apps/core/cilium/l2-announcement-policy.yaml`.
- For new services that need LAN access, add `type: LoadBalancer` to the Service.
- LAN DNS for `*.hl.mkoelle.com` is a wildcard on the FreshTomato router's dnsmasq: `address=/.hl.mkoelle.com/192.168.1.200` (the `homelab` Gateway's LB IP). It covers every depth of subdomain (e.g. `jellyfin.media.hl.mkoelle.com`), so new `hl` hostnames need **no** router change. Public DNS for these names stays NXDOMAIN.
- In-cluster DNS for the same names is separate: `apps/core/coredns-custom/configmap.yaml` uses CoreDNS's `hosts` plugin, which matches literal names only -- add a line there only when something *inside* the cluster must resolve a new `hl` hostname.

### 7. Tenants (homelab-media)

- Media apps live in the private repo `mkoelle/homelab-media`; see ADR 0008 (`docs/adrs/0008-multi-repo-tenancy.md`).
- **homelab owns the fence, the tenant owns everything inside it.** homelab owns: AppProject `media` + `media-root` (`apps/.argocd/media.yaml`), namespaces/PSA/quota and the SMB credentials Secret in `media` (`apps/core/tenant-media`), the `local-path` provisioner (`apps/core/local-path`), the Gateway `https-media` listener, and secret-store scoping. homelab does **not** hold per-app media config (no PVs, no Homepage entries).
- Don't add media workloads here, and don't loosen the `media` AppProject (cluster-scoped kinds, extra destinations) to make a tenant change work -- change the fence deliberately, in this repo, with the reasoning in a comment.
- The tenant declares its own storage: inline SMB CSI volumes (NAS shares) and `local-path` PVCs (app state, node-local, not backed up). A new NAS share needs only a NAS permission for the media SMB user; more storage needs its quota in `apps/core/tenant-media/resourcequota.yaml`. Add a zeroed quota line there for any new StorageClass.
- The `bitwarden-secretsmanager` ClusterSecretStore has a namespace allowlist (`conditions`) -- add a homelab namespace there when a new homelab app needs secrets. `media` is on it only for homelab's own SMB-creds ExternalSecret; that's safe only while the `media` AppProject blacklists `external-secrets.io` -- change those together, never one alone.

## Style Guidelines

- Prefer `kustomize` for overlaying changes on top of Helm charts.
- Keep `values.yaml` minimal — only override what is necessary.
- Use explicit namespaces in Kustomization files.

## Default Resource Sizes

Unless benchmarks justify higher values:

```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "1Gi"
    cpu: "1000m"
```

## Default Security Context

Apply to all new Deployments:

```yaml
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
```

## Health Probes

Add to all new Deployments. Check the app's health endpoint:

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 30
readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10
```
