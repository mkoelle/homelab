# ArgoCD

Argo CD is the GitOps controller. Once running, it owns all subsequent cluster state. Manual `kubectl apply` after this point should be avoided — changes go through Git.

## Prerequisites

Before applying ArgoCD, create the Bitwarden access token secret. External Secrets Operator syncs on startup and will fail permanently without it.

```bash
kubectl create namespace external-secrets

kubectl create secret generic bitwarden-access-token \
    --namespace external-secrets \
    --from-literal=token=<your-bitwarden-sm-access-token>
```

```powershell
# PowerShell
kubectl create namespace external-secrets

kubectl create secret generic bitwarden-access-token `
    --namespace external-secrets `
    --from-literal=token=<your-bitwarden-sm-access-token>
```

## Step 1 — Build and install ArgoCD

Run from the **repo root**. The build output lands at `apps/core/argocd/.build/deployment.yaml`.

```bash
task build

# --server-side required: manifest is ~1.8MB and exceeds client-side annotation limit
kubectl apply --server-side -f apps/core/argocd/.build/deployment.yaml

# Wait for ArgoCD to be ready
kubectl rollout status deployment/argocd-server -n core-argocd --timeout=5m
```

```powershell
# PowerShell
task build

kubectl apply --server-side -f apps/core/argocd/.build/deployment.yaml

kubectl rollout status deployment/argocd-server -n core-argocd --timeout=5m
```

## Step 2 — Bootstrap App-of-Apps

Apply the AppProject first — `root-application.yaml` references it and ArgoCD will reject the Application if the project doesn't exist yet.

```bash
kubectl apply -f apps/.argocd/appproject.yaml
kubectl apply -f apps/.argocd/root-application.yaml
```

ArgoCD will now sync `apps/.argocd/`, which creates the `ApplicationSet` managing all other apps. From here, Git is the source of truth.

## Step 3 — Get initial admin credentials and update password

```bash
# Get the auto-generated initial admin password
kubectl -n core-argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d

# Port-forward the ArgoCD server
kubectl port-forward svc/argocd-server -n core-argocd 8080:443 &

# Log in and set a strong password
argocd login localhost:8080 \
    --username admin \
    --password <initial-password> \
    --insecure

argocd account update-password \
    --current-password <initial-password> \
    --new-password <strong-password>
```

```powershell
# PowerShell
kubectl -n core-argocd get secret argocd-initial-admin-secret `
    -o jsonpath="{.data.password}" | `
    % { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }

kubectl port-forward svc/argocd-server -n core-argocd 8080:443

# In a new terminal
argocd login localhost:8080 `
    --username admin `
    --password <initial-password> `
    --insecure

argocd account update-password `
    --current-password <initial-password> `
    --new-password <strong-password>
```

> The initial password comes from a Secret auto-deleted after first login in some ArgoCD versions. Set a permanent password before closing the terminal.

## Step 4 — Replace SMB credential placeholders

Before the `external-secrets` app can sync, replace the placeholder UUIDs in `apps/core/external-secrets/smb-creds.yaml` with real Bitwarden Secrets Manager item IDs:

```yaml
data:
  - secretKey: username
    remoteRef:
      key: "<REPLACE-WITH-BSM-UUID-FOR-SMB-USERNAME>" # ← replace
  - secretKey: password
    remoteRef:
      key: "<REPLACE-WITH-BSM-UUID-FOR-SMB-PASSWORD>" # ← replace
```

`task build` will fail until these are replaced (intentional guard). Commit the real UUIDs, then ArgoCD reconciles and the `smb-creds` Secret materializes in `core-secrets`.

## Troubleshooting

### Namespace stuck in Terminating

ArgoCD finalizers block namespace deletion. Remove them:

```bash
kubectl get applications.argoproj.io -n core-argocd -o name | \
    xargs -I{} kubectl patch {} -n core-argocd \
    --type=json -p '[{"op":"remove","path":"/metadata/finalizers"}]'
```

```powershell
kubectl get applications.argoproj.io -n core-argocd -o name |
ForEach-Object {
    kubectl patch $_ -n core-argocd --type=json -p '[{"op":"remove","path":"/metadata/finalizers"}]'
}
```

### ArgoCD rejects root-application

If `kubectl apply -f apps/.argocd/root-application.yaml` fails with `project 'homelab' does not exist`:

```bash
# AppProject must exist first
kubectl apply -f apps/.argocd/appproject.yaml
kubectl apply -f apps/.argocd/root-application.yaml
```

## References

- [Argo CD Getting Started](https://argo-cd.readthedocs.io/en/stable/getting_started/)
- [Github - Argo Helm](https://github.com/argoproj/argo-helm)
