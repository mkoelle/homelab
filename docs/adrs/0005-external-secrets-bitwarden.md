# ADR 0005: External Secrets Operator + Bitwarden Secrets Manager

## Status

Accepted

## Context

Kubernetes workloads require credentials (e.g., NAS SMB username/password, future API keys). Storing these directly in git as `Secret` manifests would expose them in plaintext, even in a private repo. A secrets management solution is needed that:

- Keeps secrets out of git entirely.
- Integrates with a secrets store the homelab operator already uses.
- Works with ArgoCD's GitOps model (no out-of-band kubectl commands).
- Supports Kubernetes-native consumption (referenced by name in pods).

### Options Considered

- **Sealed Secrets** — encrypts secrets in git; simple setup but requires re-encryption on key rotation and ties secrets to a cluster keypair.
- **Vault (HashiCorp)** — feature-rich, well-supported ESO backend, but heavy to operate as a homelab singleton with no HA.
- **External Secrets Operator + Bitwarden Secrets Manager** — lightweight operator, Bitwarden is already used for personal password management, BSM is free for personal use, minimal operational overhead.
- **SOPS + age/GPG** — file encryption at rest in git; simpler than ESO but requires custom scripting to inject secrets into cluster on each apply.

## Decision

Use **External Secrets Operator (ESO)** with **Bitwarden Secrets Manager (BSM)** as the secrets backend.

- ESO runs in-cluster and watches `ExternalSecret` CRDs.
- A `ClusterSecretStore` backed by Bitwarden SDK Server handles auth.
- Secrets are materialized into a dedicated `core-secrets` namespace.
- Consuming apps reference `core-secrets/<secret-name>` via `secretRef`.

## Rationale

- **No secrets in git**: `ExternalSecret` manifests contain only BSM UUIDs (not values).
- **Operator overhead is low**: ESO runs as a single lightweight Deployment.
- **Existing tool**: Bitwarden is already used for homelab credentials; BSM adds a free secrets-management tier.
- **ArgoCD compatible**: ESO resources are standard CRDs, sync'd normally by ArgoCD.
- **Rotation**: Updating a secret in BSM is reflected in the cluster on the next `refreshInterval` without any git changes.

## BSM Naming Convention

Secrets in BSM use a path-like naming scheme that mirrors the repo's `apps/<category>/<app>/` structure:

```txt
<category>/<app-or-service>/<key>
```

All secrets live in a single BSM project named `homelab`. Additional projects are only warranted if per-project RBAC is needed (not required for a single-node homelab).

**Current secrets:**

| BSM Secret Name                 | Materialized as                       |
| ------------------------------- | ------------------------------------- |
| `storage/synology-smb/username` | `core-secrets/smb-creds` → `username` |
| `storage/synology-smb/password` | `core-secrets/smb-creds` → `password` |

**Future pattern:**

```txt
apps/grafana/admin-password
apps/postgres/password
infra/cloudflare/api-token
infra/oidc/client-secret
infra/tailscale/auth-key
```

## Consequences

- BSM UUID references in `ExternalSecret` manifests must be replaced with real IDs before applying (not committed as placeholders).
- The `bitwarden-access-token` secret must be bootstrapped manually before ESO can pull any secrets.
- All new secrets should use this pattern; raw `Secret` manifests are prohibited in git.
- New secrets must follow the `<category>/<app-or-service>/<key>` naming convention in BSM.
