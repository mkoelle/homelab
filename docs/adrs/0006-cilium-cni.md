# ADR 0006: Cilium as CNI and Load Balancer

## Status

Accepted

## Context

A Kubernetes CNI plugin is required for pod networking. Additionally, LoadBalancer-type Services need an in-cluster IP assignment mechanism to work on bare-metal (no cloud provider). The homelab runs a single-node Talos cluster on a home LAN with a consumer router (FreshTomato) that does not support BGP.

### Options Considered

**CNI plugins:**

- **Flannel** — simple, well-known, no network policy support, no eBPF.
- **Calico** — mature, supports network policy, BGP-capable; eBPF mode available but complex.
- **Cilium** — eBPF-native, kube-proxy replacement, network policy, Gateway API, Hubble observability, LB-IPAM built-in.

**LoadBalancer IP announcement:**

- **MetalLB** — widely used on bare-metal; separate component, supports both L2 and BGP.
- **Cilium LB-IPAM + L2 Announcements** — native to Cilium; eliminates MetalLB as a separate dependency.
- **BGP (via Cilium or MetalLB)** — requires router BGP support; home router has none.

## Decision

Use **Cilium** as the CNI, kube-proxy replacement, and LoadBalancer IP manager.
Use **Cilium L2 Announcements** (ARP) for LoadBalancer IP advertisement — no BGP.

LB IP pool: `192.168.1.200–192.168.1.254`.

## Rationale

- **eBPF performance**: Lower latency and CPU overhead vs. iptables-based CNIs.
- **kube-proxy replacement**: Eliminates a component; Cilium handles service routing natively.
- **Built-in LB-IPAM**: No MetalLB needed; fewer moving parts.
- **L2 Announcements fit the environment**: Home router handles ARP normally; L2 works out of the box without BGP.
- **Gateway API support**: Enables HTTPRoute-based ingress without a separate ingress controller.
- **Hubble**: Built-in observability (flow logs, UI) at no extra cost.
- **Talos compatibility**: Cilium is the recommended CNI for Talos; well-documented integration path.

## Consequences

- Cilium requires specific Talos security context capabilities (documented in `values.yaml`).
- XDP acceleration set to `best-effort` to fix L2 ARP issue in Talos 1.9+ (see values.yaml comment).
- Cilium is managed via a dedicated ArgoCD Application (`cilium-application.yaml`) outside the main ApplicationSet to avoid bootstrap ordering issues.
- L2 announcements only work reliably on a flat L2 network segment — acceptable for single-node homelab.
- BGP must never be configured; home router (FreshTomato) does not support it.
