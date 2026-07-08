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
