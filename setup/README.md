# Initial system setup

Start from a bare-metal machine and follow the minimal path below to
bring up a Kubernetes control plane (Talos) and a GitOps controller
(ArgoCD).

Steps

1. Install Talos and bootstrap the cluster — see [talos](./talos/README.md) for the full
  installation and configuration instructions. After this step you should have
  a running control plane and a `kubeconfig` you can use from the admin
  machine.
2. Install ArgoCD to enable GitOps workflows — see [argocd](./argocd/README.md) for
  the installation steps. ArgoCD runs on the cluster created in step 1 and
  provides the UI and APIs to sync applications from git.
