# ADR: Choosing Talos OS for Base Operating System

## Context

The goal of this homelab is to run a Kubernetes-based environment with strong security, minimal maintenance overhead, and a modern approach to infrastructure management. Several OS options were considered, including:

- **Flatcar Container Linux** – Immutable, container-focused, widely used for Kubernetes nodes.
- **AWS Bottlerocket** – Secure and minimal OS optimized for containers, but tightly coupled with AWS ecosystem.
- **k3OS / k3s** – Lightweight Kubernetes distribution with integrated OS, good for edge and small clusters.
- **Ubuntu / Debian** – General-purpose Linux distributions, flexible but require manual hardening.
- **Talos OS** – Immutable, minimal OS designed specifically for Kubernetes, with a strong security posture.

## Decision

I chose **Talos OS** as the base operating system for the homelab Kubernetes cluster.

## Rationale

- **Security as a Priority**
    - Talos OS is designed with a security-first approach:
        - No SSH access; all management is API-driven.
        - Immutable filesystem reduces attack surface.
        - No package manager, reducing vulnerabilities.
- **Kubernetes-Native Design**
    - Built specifically for Kubernetes, simplifying cluster lifecycle management.
    - Declarative configuration aligns with GitOps principles.
- **Operational Simplicity**
    - Automated upgrades and consistent state management.
    - API-driven operations reduce manual intervention and configuration drift.
- **Community & Documentation**
    - Active development and strong community support.
    - Clear documentation for homelab and production use cases.

## Alternatives Considered

- **Flatcar**: Secure and immutable, but there is no straightforward way to provide an Ignition config making bare metal installs difficult.
- **Bottlerocket**: Excellent security, but AWS-centric and less flexible for on-prem homelab.
- **k3OS**: Lightweight and integrated, but less mature and limited in advanced security features.
- **Traditional Linux**: Flexible but requires significant hardening and manual maintenance.

## Consequences

- **Pros**:
    - Strong security posture out of the box.
    - Simplified Kubernetes operations.
    - Reduced attack surface and configuration drift.
- **Cons**:
    - Limited flexibility for non-Kubernetes workloads.
    - Learning curve for API-driven management.
    - Smaller ecosystem compared to general-purpose Linux distributions.