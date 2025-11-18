# Cilium

Cilium is a networking plugin that implements the Container Networking Interface (CNI)
for Kubernetes. It provides network connectivity and security policies using eBPF
(extended Berkeley Packet Filter) for high performance and low overhead.

Cilium is used in this homelab for:

- High-performance networking with eBPF acceleration
- Network security policies without kube-proxy
- Observability and troubleshooting capabilities
- Gateway API support for advanced routing

## Install Cilium

Installation is done through Helm so that it can later be managed by ArgoCD.

```pwsh
# Add cilium to helm
helm repo add cilium https://helm.cilium.io/
helm repo update

# Use helm to install cilium to our cluster
# This contains the params to deploy without kube-proxy,
# with GatewayAPI support, and only one operator replica.
helm install `
    cilium `
    cilium/cilium `
    --version 1.18.0 `
    --namespace kube-system `
    --set ipam.mode=kubernetes `
    --set kubeProxyReplacement=true `
    --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" `
    --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" `
    --set cgroup.autoMount.enabled=false `
    --set cgroup.hostRoot=/sys/fs/cgroup `
    --set k8sServiceHost=localhost `
    --set k8sServicePort=7445 `
    --set operator.replicas=1 `
    --set=gatewayAPI.enabled=true `
    --set=gatewayAPI.enableAlpn=true `
    --set=gatewayAPI.enableAppProtocol=true
```

## Verification

```pwsh
# Verify Cilium pods are running:
kubectl get pods -n kube-system -l k8s-app=cilium

# Check Cilium status and connectivity:
kubectl exec -n kube-system ds/cilium -- cilium status
```

## References

### Official Documentation

- [Talos Cilium Install Guide](https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium)
- [Cilium Quickstart Guide](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/)
- [Cilium Helm Chart Values](https://docs.cilium.io/en/stable/helm-reference/)

### Advanced Topics

- [Network Policies](https://docs.cilium.io/en/stable/policy/)
- [Gateway API Support](https://docs.cilium.io/en/stable/gettingstarted/gateway-api/)
- [Performance Tuning](https://docs.cilium.io/en/stable/operations/)
