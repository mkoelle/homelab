# ADR: Using Argo CD for GitOps in Homelab

## Context

The homelab runs Kubernetes workloads and requires a reliable, automated way to manage application deployments. The primary goals are:

- Consistent and declarative configuration management.
- Easy rollback and version control.
- Reduced manual intervention for updates and sync.

Options considered:

- **Manual `kubectl apply` workflows** – Directly applying manifests from local machine.
- **Flux CD** – Another GitOps tool with similar capabilities.
- **Helm-only approach** – Using Helm charts without GitOps automation.
- **Argo CD** – GitOps continuous delivery tool with UI and CLI support.

## Decision

I chose **Argo CD** as the GitOps solution for managing Kubernetes deployments in the homelab.

## Rationale

- **Automation & Consistency**
  - Eliminates manual `kubectl` commands by continuously reconciling cluster state with Git.
  - Ensures desired state is always applied, reducing configuration drift.
- **Performance & Developer Experience**
  - Provides a clean web UI and CLI for monitoring and managing apps.
  - Faster deployments and easier troubleshooting compared to manual workflows.
- **Rollback & Version Control**
  - Git history enables quick rollback to previous versions.
  - Aligns with best practices for immutable infrastructure.
- **Flexibility**
  - Supports Helm, Kustomize, and raw manifests.
  - Works well with Talos OS and lightweight clusters.
- **Community & Documentation**
  - Strong community support and clear documentation for homelab and production use cases.

## Alternatives Considered

- **Manual `kubectl apply`**:
  - **Pros**: Simple, no extra components.
  - **Cons**: Error-prone, no automation, hard to track changes.
- **Flux CD**:
  - **Pros**: Lightweight, strong GitOps model.
  - **Cons**: Less intuitive UI, smaller ecosystem compared to Argo CD.
- **Helm-only**:
  - **Pros**: Good for templating.
  - **Cons**: No continuous sync or GitOps workflow.

## Consequences

- **Pros**:
  - Automated deployments and sync.
  - Visual dashboard for app health.
  - Easier rollback and auditability.
- **Cons**:
  - Additional component to manage.
  - Requires learning GitOps workflows.
