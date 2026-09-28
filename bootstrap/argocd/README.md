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

The TLS cert for `bitwarden-sdk-server` (required — the ESO Bitwarden provider always builds an HTTPS client and fails with `failed to append caBundle` without one, even though the server is cluster-internal only) is issued automatically by cert-manager (`apps/core/external-secrets/bitwarden-tls-cert.yaml`, off this cluster's self-signed CA) — no manual step needed.

> **First-sync-only caveat:** cert-manager's `argocd-application-controller` can hit the same RBAC-escalation bootstrap paradox as ArgoCD's own `deletecollection` fix (see backlog/troubleshooting docs) — Kubernetes won't let ArgoCD grant a permission (here, `approve`/`sign` on `signers`) it doesn't itself hold yet. If the `cert-manager` Application's first sync fails with a `ClusterRole ... is forbidden: ... attempting to grant RBAC permissions not currently held` error, break it with one direct admin apply: `kubectl apply --server-side --force-conflicts -f apps/core/cert-manager/.build/deployment.yaml`. Every sync after that succeeds normally — this is a one-time bootstrap quirk, not a recurring issue.

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

## Step 4 — Verify External Secrets

The repository's SMB credentials are defined in
`apps/core/external-secrets/smb-photos-creds.yaml`; Zitadel and other app
credentials are declared in their respective manifests. Their Bitwarden SM
item IDs are already populated. Do not replace UUIDs in the manifests: those
are item identifiers, not the secret values. To verify a fresh install, check
that the ExternalSecrets report `Ready=True` and that their target Secrets
exist before diagnosing a workload that depends on them:

```bash
kubectl get externalsecrets -A
kubectl get secret smb-photos-creds -n core-secrets
```

`task build` rejects placeholder markers and zero UUIDs, but does not validate
that Bitwarden item IDs are valid or that credentials can authenticate to the
NAS.

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
