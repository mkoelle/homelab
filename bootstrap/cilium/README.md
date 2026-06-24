# Cilium

Cilium is the CNI for this cluster. It handles pod networking, kube-proxy replacement, L2 LoadBalancer IP announcements (ARP), and Hubble observability.

Cilium must be installed **before ArgoCD** — without a CNI, no pods can schedule, so ArgoCD itself won't start.

## Install

Installation uses Helm against `apps/core/cilium/values.yaml` as the single source of truth. This ensures the bootstrap install matches what ArgoCD manages going forward — no drift.

Run from the **repo root**:

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update

helm install cilium cilium/cilium \
    --version 1.19.3 \
    --namespace kube-system \
    -f apps/core/cilium/values.yaml
```

```powershell
# PowerShell
helm repo add cilium https://helm.cilium.io/
helm repo update

helm install cilium cilium/cilium `
    --version 1.19.3 `
    --namespace kube-system `
    -f apps/core/cilium/values.yaml
```

> **Do not** add individual `--set` flags — they diverge from `values.yaml` and create state ArgoCD will fight to reconcile. The values file is the record of why each setting exists.

## Verify L2 Announcements

L2 announcement policy matches interfaces via regex `^eth[0-9]+`. If your NIC uses predictable names (`enp*`, `eno*`, `ens*`), LoadBalancer IPs will stay `<pending>` silently.

```bash
# Check actual interface name on the node
talosctl -n motherbox.local get links | grep -v loopback

# If interface is not eth0/eth1/etc., update the policy:
# apps/core/cilium/l2-announcement-policy.yaml → spec.interfaces
```

## Verify Installation

```bash
# Cilium pods running
kubectl get pods -n kube-system -l k8s-app=cilium

# Cilium agent healthy
kubectl exec -n kube-system ds/cilium -- cilium status

# L2 announcement policy active (after LB IP pool is deployed by ArgoCD)
kubectl exec -n kube-system ds/cilium -- cilium l2announce list
```

## References

- [Talos Cilium Install Guide](https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium)
- [Cilium Helm Chart Values](https://docs.cilium.io/en/stable/helm-reference/)
- [L2 Announcements](https://docs.cilium.io/en/stable/network/l2-announcements/)
