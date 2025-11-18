# ADR: Choosing Storage Protocol for Persistent Volumes in Homelab

## Context

The homelab uses a **Synology NAS** as the primary storage backend for Kubernetes workloads. The goal is to deliver high performance, reliability, and secure persistent volumes for containers. Given the NAS constraint, the main options considered were:

- **NFS (Network File System)** – File-level protocol, widely supported, simple to configure.
- **iSCSI (Internet Small Computer Systems Interface)** – Block-level protocol offering higher throughput and lower latency.

## Decision

I choose **iSCSI** as the storage protocol for Kubernetes persistent volumes.

## Rationale

- **Performance**  
  - iSCSI provides block-level access, which significantly improves I/O performance compared to NFS.
  - Better suited for workloads with high read/write demands (e.g., databases, caching layers).
- **Reliability**  
  - Supports multipath configurations for failover and redundancy.
  - Works well with Synology’s LUN-based snapshots for consistent backups.
- **Flexibility**  
  - Allows fine-grained control over storage allocation and performance tuning.
- **Kubernetes Integration**  
  - CSI drivers for iSCSI are mature and widely supported.

## Alternatives Considered

- **NFS**:
  - **Pros**: Simple setup, native integration with Kubernetes, easy permission management.
  - **Cons**: Lower performance for heavy I/O workloads, file-level locking overhead.
- **iSCSI**:
  - **Pros**: High performance, block-level access, ideal for databases and VM storage.
  - **Cons**: More complex setup (LUN provisioning, multipath configuration), requires careful failover handling.

## Consequences

- **Pros**:
  - Improved performance for demanding workloads.
  - Better alignment with future plans for running stateful apps and VMs.
- **Cons**:
  - Increased operational complexity compared to NFS.
  - Requires additional configuration for multipath and security.
