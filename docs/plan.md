# Homelab Implementation Plan

Phased roadmap derived from security audit backlog. Each phase has hard prerequisites; do not skip ahead.

---

## Immediate: Manual Steps (Unblock Everything)

These require out-of-band action before any automated work proceeds.

| Task                                                     | File                                        | Unblocks                |
| -------------------------------------------------------- | ------------------------------------------- | ----------------------- |
| Replace BSM UUIDs in smb-creds ExternalSecret            | `apps/core/external-secrets/smb-creds.yaml` | Storage on fresh deploy |
| Provision NAS share `//asgard.local/appdata/filebrowser` | Synology DSM                                | Filebrowser /config PVC |

---

## Phase 1 — Housekeeping (No External Dependencies)

Automate or harden with what exists today. No new services.

### 1a. Scope kube-linter exclusions

**Backlog:** High — "Scope kube-linter global security exclusions"

Remove global exclusions from `.config/kube-linter.yaml`. Add per-object annotations on vendor resources:

```yaml
# on the specific Deployment/DaemonSet that needs it
metadata:
  annotations:
    kube-linter.io/ignore-check: "run-as-non-root,no-read-only-root-fs"
```

Affected vendor resources: Cilium DaemonSets, ArgoCD Deployments, ESO Deployments, csi-driver-smb DaemonSet.

Wave: single PR; run `task validate` after each annotation to confirm CI stays green.

### 1b. kube-system default-deny NetworkPolicy

**Backlog:** Medium — "Add default-deny NetworkPolicy for kube-system"

**High blast radius** — test on cluster before merging.

```yaml
# apps/core/coredns-custom/networkpolicy.yaml (or new kube-system app)
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: kube-system
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
kind: NetworkPolicy
metadata:
  name: allow-coredns
  namespace: kube-system
spec:
  podSelector:
    matchLabels:
      k8s-app: kube-dns
  policyTypes: [Ingress]
  ingress:
    - ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
```

### 1c. Etcd backup CronJob

**Backlog:** Medium — "Automate etcd backup"

```yaml
# apps/core/etcd-backup/cronjob.yaml
kind: CronJob
spec:
  schedule: "0 3 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          hostNetwork: true
          containers:
            - name: backup
              image: ghcr.io/siderolabs/talosctl:<version>
              command:
                - talosctl
                - etcd
                - snapshot
                - /backup/etcd-$(date +%Y%m%d).db
                - --nodes=192.168.1.2
              volumeMounts:
                - name: backup
                  mountPath: /backup
          volumes:
            - name: backup
              persistentVolumeClaim:
                claimName: etcd-backup
```

Also store `controlplane.yaml` + `talosconfig` in Bitwarden (not git).

### 1d. Vendor ArgoCD manifests

**Backlog:** Medium — "Vendor ArgoCD upstream manifests (remove live GitHub fetch)"

```bash
# one-time: inflate and vendor
mkdir -p apps/core/argocd/vendor
kustomize build github.com/argoproj/argo-cd//manifests/cluster-install?ref=v3.3.8 > apps/core/argocd/vendor/install.yaml
```

Update `apps/core/argocd/kustomization.yaml`:

```yaml
resources:
  - namespace.yaml
  - networkpolicy.yaml
  - vendor/install.yaml # replaces github.com/... remote
```

Add Renovate regex manager to track `ref=v3.3.8` → bump vendored file on new ArgoCD releases.

---

## Phase 2 — cert-manager + TLS Everywhere

**Prerequisite:** Phase 1 complete, BSM UUIDs replaced.

### 2a. Deploy cert-manager (wave 1)

New app: `apps/core/cert-manager/`

```yaml
# kustomization.yaml
helmCharts:
  - name: cert-manager
    repo: https://charts.jetstack.io
    version: v1.x.x
    releaseName: cert-manager
    namespace: cert-manager
    valuesFile: values.yaml
```

```yaml
# values.yaml
installCRDs: true
resources:
  requests:
    memory: 256Mi
    cpu: 100m
  limits:
    memory: 512Mi
    cpu: 500m
```

ArgoCD sync wave: `1` (after CSI, before workloads).

Add `cert-manager` namespace to AppProject destinations.

### 2b. Enable Bitwarden SDK TLS

**Backlog:** Critical — "Enable TLS on Bitwarden SDK server"

After cert-manager is running:

1. Create `Certificate` CR for `bitwarden-sdk-server.external-secrets.svc.cluster.local`.
2. Update `apps/core/external-secrets/values.yaml`:

```yaml
bitwarden-sdk-server:
  image:
    tls:
      enabled: true
```

1. Update `ClusterSecretStore` URL: `http://` → `https://`.

### 2c. Deploy Gateway API (GatewayClass + Gateway)

**Backlog:** Low — "Disable Gateway API or deploy GatewayClass + Gateway"

Cilium already has `gatewayAPI.enabled: true`. Deploy the GatewayClass and a Gateway:

```yaml
# apps/core/gateway/gatewayclass.yaml
kind: GatewayClass
metadata:
  name: cilium
spec:
  controllerName: io.cilium/gateway-controller
---
# apps/core/gateway/gateway.yaml
kind: Gateway
metadata:
  name: homelab
  namespace: core-gateway
spec:
  gatewayClassName: cilium
  listeners:
    - name: https
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs:
          - name: homelab-tls
```

ArgoCD sync wave: `2`.

### 2d. Filebrowser TLS + credentials

**Backlog:** Medium — "Configure filebrowser credentials and TLS"

1. Create ExternalSecret for `filebrowser-admin` (BSM item with username/password).
2. Mount `filebrowser.json` from Secret into Deployment.
3. Add HTTPRoute pointing to `filebrowser` Service with TLS termination at Gateway.
4. Change Service type from `LoadBalancer` to `ClusterIP` once HTTPRoute is live.

### 2e. Hubble UI via HTTPRoute

**Backlog:** Planned

```yaml
# apps/core/cilium/hubble-httproute.yaml
kind: HTTPRoute
metadata:
  name: hubble-ui
  namespace: kube-system
spec:
  parentRefs:
    - name: homelab
      namespace: core-gateway
  hostnames: ["hubble.homelab.local"]
  rules:
    - backendRefs:
        - name: hubble-ui
          port: 80
```

---

## Phase 3 — Observability

**Prerequisite:** Phase 2 complete (Gateway for Grafana HTTPRoute).

### 3a. kube-prometheus-stack (wave 3)

New app: `apps/core/monitoring/`

```yaml
# values.yaml — minimal homelab config
prometheus:
  prometheusSpec:
    retention: 7d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: smb-nas
          resources:
            requests:
              storage: 20Gi
grafana:
  enabled: true
  adminPassword: "" # via ExternalSecret
alertmanager:
  config:
    receivers:
      - name: slack
        slack_configs: [] # fill after Phase 4
```

Key alerts to configure:

- Pod CrashLoopBackOff
- Node memory > 80%
- etcd latency > 1s
- ArgoCD OutOfSync > 10 min
- PVC usage > 80%

### 3b. Loki + Promtail

```yaml
# apps/core/monitoring/loki-values.yaml
loki:
  storage:
    type: filesystem
  persistence:
    enabled: true
    storageClassName: smb-nas
    size: 50Gi
```

Once Loki is running, upgrade audit log level for Secrets (`RequestResponse`) per the Low backlog item.

### 3c. Cilium integration

In `apps/core/cilium/values.yaml`:

```yaml
prometheus:
  enabled: true
  port: 9962
hubble:
  metrics:
    enabled:
      - dns
      - drop
      - tcp
      - flow
      - icmp
      - http
  serviceMonitor:
    enabled: true
```

---

## Phase 4 — Identity (Authentik)

**Prerequisite:** Phase 3 complete (metrics for Authentik health).

### 4a. Deploy Authentik (wave 4)

New app: `apps/core/authentik/`

Requires PostgreSQL (bundled in chart) + Redis (shared or bundled). Configure ExternalSecret for Authentik secret key + DB password.

### 4b. ArgoCD OIDC via Dex

**Backlog:** Medium — "Configure ArgoCD OIDC/SSO and RBAC policy"

Update `apps/core/argocd/argocd-cm.yaml`:

```yaml
oidc.config: |
  name: Authentik
  issuer: https://auth.homelab.local/application/o/argocd/
  clientID: argocd
  clientSecret: $oidc.authentik.clientSecret
  requestedScopes: [openid, profile, email, groups]
```

Add `argocd-rbac-cm`:

```yaml
policy.default: role:readonly
policy.csv: |
  g, homelab-admins, role:admin
```

Short-term (before Authentik): set `policy.default: role:''` to deny anonymous access.

---

## Phase 5 — Remote Access

**Prerequisite:** Phase 4 complete.

### 5a. Tailscale operator

New app: `apps/core/tailscale/`

```yaml
# values.yaml
operatorConfig:
  hostname: homelab-k8s
```

Expose ArgoCD and Grafana via Tailscale `ProxyGroup` instead of LAN LoadBalancer for remote access without port-forwarding.

### 5b. ArgoCD notifications

```yaml
# apps/core/argocd/argocd-notifications-cm.yaml
triggers:
  - name: on-sync-failed
    condition: app.status.operationState.phase in ['Error', 'Failed']
    template: app-sync-failed
```

Slack webhook via ExternalSecret.

---

## Dependency Graph

```txt
BSM UUIDs ──────────────────────────────────────────► Storage works
NAS share ──────────────────────────────────────────► Filebrowser /config

Phase 1 (no deps)
  ├── kube-linter scoping
  ├── kube-system NetworkPolicy
  ├── etcd backup
  └── vendor ArgoCD manifests
         │
         ▼
Phase 2 (cert-manager)
  ├── cert-manager ──► Bitwarden TLS
  │                 ├► Filebrowser TLS
  │                 └► Gateway + HTTPRoutes
  │                         │
  │                         ▼
Phase 3 (observability) ────┤
  ├── kube-prometheus-stack  │
  ├── Loki + Promtail        │
  └── Cilium integration     │
         │                   │
         ▼                   │
Phase 4 (identity) ──────────┘
  ├── Authentik
  └── ArgoCD OIDC
         │
         ▼
Phase 5 (remote access)
  ├── Tailscale
  └── ArgoCD notifications
```

---

## Wave Assignment Summary

| Wave | App                              | Phase          |
| ---- | -------------------------------- | -------------- |
| -10  | AppProject homelab               | Done           |
| -1   | external-secrets                 | Done           |
| 0    | cilium, argocd                   | Done           |
| 1    | csi-driver-smb, cert-manager     | Phase 2        |
| 2    | gateway (GatewayClass + Gateway) | Phase 2        |
| 3    | kube-prometheus-stack, loki      | Phase 3        |
| 4    | authentik                        | Phase 4        |
| 5    | tailscale                        | Phase 5        |
| 6+   | filebrowser, other workloads     | Done / Phase 2 |
