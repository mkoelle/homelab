# Bootstrap

Start from a bare-metal machine and follow these steps in order to bring up the cluster.

## Steps

1. **Talos** — install the OS and bootstrap Kubernetes — [talos/README.md](./talos/README.md)
   After this step: running control plane, working `kubeconfig`.

2. **Cilium** — install the CNI — [cilium/README.md](./cilium/README.md)
   Required before ArgoCD: no CNI = no pod scheduling.
   After this step: pod networking active, L2 LoadBalancer IPs operational.

3. **ArgoCD** — install the GitOps controller and hand off to Git — [argocd/README.md](./argocd/README.md)
   **Prerequisite:** create the Bitwarden access token Secret before applying (see argocd/README.md).
   After this step: all apps in `apps/` sync automatically from Git. Manual `kubectl apply` no longer needed.

## Prerequisites on the admin machine

- `talosctl` — version matching the cluster (currently `v1.13.3`)
- `kubectl`
- `helm` (v3)
- `task` (go-task)
- Docker or Podman (used by `task build`)
- `argocd` CLI (for password setup in step 3)

## What is and isn't in Git

| File | In Git | Notes |
|---|---|---|
| `bootstrap/talos/patch.yaml` | yes | patch applied during gen config |
| `bootstrap/talos/controlplane.yaml` | **no** (gitignored) | contains cluster PKI private keys |
| `bootstrap/talos/talosconfig` | **no** (gitignored) | contains admin client certificate and key |
| `bootstrap/talos/worker.yaml` | **no** (gitignored) | |
| `apps/**/*.yaml` | yes | all app manifests, managed by ArgoCD |

Store `controlplane.yaml` and `talosconfig` in Bitwarden. Losing them on disk = no way to manage the Talos node.
