# ArgoCD

Argo CD is a declarative, GitOps-focused continuous delivery tool designed specifically for Kubernetes. It continuously monitors your Git repositories and automatically synchronizes your cluster state with the desired state defined in your manifests. Unlike traditional CI/CD tools, Argo CD treats Git as the single source of truth, providing automatic drift detection and self-healing capabilities.

I use Argo CD as the continuous delivery engine for my homelab because it provides:

- GitOps Workflow: All cluster changes are version-controlled, auditable, and reversible through Git commits.
- Automated Synchronization: Detects configuration drift and automatically reconciles cluster state with repository definitions.
- Visual Management: Web UI provides real-time visibility into application health, sync status, and deployment history.
- Declarative Everything: Manages not just applications, but also Kubernetes resources, making infrastructure truly code-driven and reproducible.

## Initial Configuration

The following instructions and steps are for setting up or starting over with on a freshly provisioned talos cluster.

<https://github.com/argoproj/argo-helm>

### Install Argo CD

```pwsh
# Create the namespace in kubernetes that we will manage argocd under
kubectl create namespace core-argocd

# Add argo to helm
helm repo add argo https://argoproj.github.io/argo-helm

# use helm to install argo-cd to our cluster
helm install argocd argo/argo-cd --namespace core-argocd

# Get the randomly generated admin password
kubectl -n core-argocd get secret argocd-initial-admin-secret `
   -o jsonpath="{.data.password}" | `
   % { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }

# Note: this is easier in bash:
# kubectl -n core-argocd get secret argocd-initial-admin-secret \
#    -o jsonpath="{.data.password}" | base64 -d
```

### Configure Argo CD

Expose Argo cd's UI by port forwarding the argocd server service,
this is easiest to do using lens:

![Expose argo cd via port forward](/docs/assets/kube-lens-port-forward.png "Expose argo cd")

Update the admin user password:

![Update the admin password](/docs/assets/argocd-update-password.png "update password")

## References

- [YouTube video - Install Argo CD on Kubernetes cluster | Deploy Application to Kubernetes using Argo CD | Helm Charts](https://www.youtube.com/watch?v=HzNszgkVuaA)
