# ADR 0008: Multi-Repo Tenancy for homelab-media

## Status

Accepted

## Context

Media workloads (Jellyfin now; the \*arr stack, Audiobookshelf, etc. later)
live in a separate private repo, [`mkoelle/homelab-media`](https://github.com/mkoelle/homelab-media).
The goal is for that repo to evolve independently -- add apps, change sync
policy, restructure its own app-of-apps -- without a homelab PR each time,
while keeping it from reaching anything outside its own lane.

Argo CD's `AppProject` is the natural fence, but whoever _defines_ the
project defines the fence: AppProjects must live in `core-argocd`, and
granting the tenant write access there lets it edit any project, including
`homelab` (the application controller holds `*/*` cluster RBAC). So a
tenant-owned AppProject is not a boundary.

### Options

- **Tenant owns its AppProject + apps** -- maximum independence, no boundary.
- **Homelab owns every media Application** (list elements in `apps.yaml`)
  -- strong boundary, but every media change needs a homelab PR.
- **Homelab owns the fence, tenant owns everything inside it**, enforced by
  Argo CD's apps-in-any-namespace.

## Decision

**Homelab owns the fence; homelab-media owns everything inside it.**

Rule of thumb: anything that grants privilege, is cluster-scoped, or is
shared between tenants belongs to homelab.

| homelab (the fence)                                                                                                                            | homelab-media                                        |
| ---------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| AppProject `media` + `media-root` handoff Application (`apps/.argocd/media.yaml`)                                                              | Its app-of-apps (`argocd/`), one Application per app |
| Namespaces `media` / `media-argocd`, PSA labels, ResourceQuota, LimitRange (`apps/core/tenant-media`)                                          | All workloads, PVCs, HTTPRoutes, NetworkPolicies     |
| Argo CD settings: apps-in-any-namespace, repo credential, Application health check                                                             | Its own CI / lint / Renovate                         |
| PVs -- read-only SMB libraries and node-local app state -- each `claimRef`-pinned to one media claim (`apps/core/storage/volumes-media*.yaml`) |                                                      |
| Gateway listener `https-media` + `*.media.hl.mkoelle.com` cert (`apps/core/gateway`)                                                           |                                                      |
| Secret-store scoping (`ClusterSecretStore` namespace conditions)                                                                               |                                                      |

Enforcement points:

- **Project escape** -- Applications in `media-argocd` may only use
  projects whose `sourceNamespaces` lists `media-argocd`; only `media` does.
- **Privilege** -- the tenant can't create namespaces (so can't relabel PSA
  to `privileged`) or PVs (PSA doesn't inspect PVC-backed volumes, so a
  `hostPath` PV would reach the node). `clusterResourceWhitelist` is empty.
- **Hostnames** -- `media` has no `gateway-access` label; its only listener
  is `https-media`, selected by the API-server-set
  `kubernetes.io/metadata.name`. Gateway API rejects routes whose hostnames
  fall outside the listener's, so the tenant can only serve
  `*.media.hl.mkoelle.com`.
- **LAN IPs** -- quota `services.loadbalancers: "0"`.
- **Secrets** -- the shared `bitwarden-secretsmanager` store is limited to
  an explicit namespace allowlist that excludes `media`. The tenant gets its
  own BSM project + store when it first needs secrets.
- **NAS** -- dedicated SMB user, read-only on the libraries and nothing
  else; library PVs also mount `readOnly` at the CSI layer. The tenant has
  no NAS write access yet (a later feature), so app state (e.g. Jellyfin's
  config/SQLite) lives on homelab-declared `local` PVs on motherbox
  (`apps/core/storage/volumes-media-local.yaml`, class `media-local`) --
  not backed up, lost on a node rebuild.

## Consequences

- **Pros**:
  - New media apps, hostnames under `*.media.hl.mkoelle.com`, and
    app-of-apps changes need no homelab change.
  - A compromised or careless tenant repo can't escalate beyond its
    namespace, touch other apps' hostnames, read homelab secrets, or write
    to media libraries.
- **Cons**:
  - A new NAS share, a namespace, or more quota still needs a homelab PR.
  - SSO for tenant apps behind oauth2-proxy still needs a Zitadel client in
    homelab's Terraform (apps with native auth, like Jellyfin, don't).
  - Two repos to keep linted; the tenant's manifests aren't covered by
    homelab's `task validate`.
  - The GitHub token (`core/argocd/github-access-token`) expires; media
    stops syncing silently until it's rotated in BSM.
