# ADR 0004: SMB Storage for All NAS-Backed Workloads

## Status

Accepted — Supersedes [ADR 0002](0002-iscsi-storage-protocol-for-persistent-volumes.md)

## Context

ADR 0002 selected iSCSI as the storage protocol for Kubernetes persistent volumes. After initial planning, iSCSI provisioning was blocked: the Synology NAS (`asgard.local`) uses a single storage pool with no capacity remaining to create iSCSI LUNs. The existing volume is fully allocated as SMB shares.

The storage protocol decision needed to be revisited with the actual hardware constraint in scope.

### Options

- **iSCSI** — block-level, high performance, requires dedicated LUN capacity on the NAS (unavailable).
- **NFS** — file-level, widely supported, no NAS capacity constraint, requires enabling NFS on Synology and managing exports.
- **SMB (via csi-driver-smb)** — file-level, shares already provisioned on the NAS, minimal new configuration, mature CSI driver, works for all planned workloads.

## Decision

Use **SMB** via `csi-driver-smb` for all NAS-backed Kubernetes storage. iSCSI is deferred until the NAS is replaced or expanded with a separate volume.

## Rationale

- **Constraint-driven**: NAS volume is full — iSCSI requires LUN allocation that cannot be done without impacting existing SMB shares.
- **Shares already exist**: All media libraries (`Movies`, `TV_Shows`, `Music`, `Books`, `Manga`, etc.) are already SMB shares. No new NAS configuration needed.
- **Workload fit**: Planned homelab workloads are read-heavy media servers, file browsers, and lightweight stateful apps. None require block-level I/O. SQLite on SMB (`smb-appdata`) is acceptable for homelab.
- **Driver maturity**: `csi-driver-smb` is maintained under kubernetes-csi, has stable Helm charts, and integrates cleanly with Kustomize + ArgoCD.

## Storage Class Layout

| StorageClass    | Access Mode   | Use case                                     |
| --------------- | ------------- | -------------------------------------------- |
| `smb-readonly`  | ReadOnlyMany  | Media libraries (Jellyfin, Komga, Navidrome) |
| `smb-readwrite` | ReadWriteMany | Downloads share, photo import                |
| `smb-appdata`   | ReadWriteOnce | App state, SQLite databases, config          |
| `local-path`    | ReadWriteOnce | PostgreSQL / high-IOPS only                  |

SQLite on `smb-appdata` is acceptable. PostgreSQL on SMB is not — use `local-path` for any Postgres instance.

## Consequences

- **Pros**:
  - No NAS reconfiguration required.
  - Existing shares reused directly.
  - Consistent GitOps workflow via ExternalSecret for SMB credentials.
  - `smb-appdata` PVCs backed by Synology snapshots — app data is protected.
- **Cons**:
  - File-level protocol; not suitable for high-IOPS workloads.
  - SMB credentials must be managed via External Secrets Operator (bootstrap dependency).
  - `local-path` data (Postgres) is ephemeral if the node is rebuilt — requires manual export to NAS.
  - iSCSI deferred indefinitely until hardware is expanded.
