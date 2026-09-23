# Declarative OIDC clients + Google IDP federation -- the whole reason this
# repo chose Zitadel over Authelia (Authelia has no external-IDP support).
# Applied by terraform-job.yaml as an ArgoCD PostSync hook, re-run whenever
# these .tf files change (see kustomization.yaml's configMapGenerator).
#
# org_id: DO NOT omit this on any resource below, despite the provider docs'
# claim that it "defaults to the organization of the authenticated user/
# service account". That default is resolved server-side at CREATE time and
# then persisted into state -- but on every subsequent plan, our own HCL
# (which never set org_id) is compared against state's now-concrete value,
# reads as a diff, and since org_id is ForceNew, silently destroys and
# recreates every resource on every single apply, forever. Confirmed live:
# this is why Grafana/ArgoCD's OIDC client_id kept rotating out from under
# them after each sync, repeatedly breaking SSO that had just been
# confirmed working. Look the org up explicitly instead, so config and
# state agree on a real, stable value from the start.
data "zitadel_orgs" "homelab" {
  name        = "homelab"
  name_method = "TEXT_QUERY_METHOD_EQUALS"
}

locals {
  org_id = tolist(data.zitadel_orgs.homelab.ids)[0]
}

resource "zitadel_project" "homelab" {
  org_id                 = local.org_id
  name                   = "homelab"
  project_role_assertion = false
  project_role_check     = false
  has_project_check      = false
}

resource "zitadel_application_oidc" "argocd" {
  org_id         = local.org_id
  project_id     = zitadel_project.homelab.id
  name           = "ArgoCD"
  redirect_uris  = ["https://argocd.motherbox.local/auth/callback"]
  response_types = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types    = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]

  app_type          = "OIDC_APP_TYPE_WEB"
  auth_method_type  = "OIDC_AUTH_METHOD_TYPE_BASIC"
  version           = "OIDC_VERSION_1_0"
  dev_mode          = false
  access_token_type = "OIDC_TOKEN_TYPE_BEARER"
}

resource "zitadel_application_oidc" "grafana" {
  org_id         = local.org_id
  project_id     = zitadel_project.homelab.id
  name           = "Grafana"
  redirect_uris  = ["https://grafana.motherbox.local/login/generic_oauth"]
  response_types = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types    = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE"]

  app_type          = "OIDC_APP_TYPE_WEB"
  auth_method_type  = "OIDC_AUTH_METHOD_TYPE_BASIC"
  version           = "OIDC_VERSION_1_0"
  dev_mode          = false
  access_token_type = "OIDC_TOKEN_TYPE_BEARER"
}

resource "zitadel_org_idp_google" "default" {
  org_id        = local.org_id
  name          = "Google"
  client_id     = trimspace(file("/var/run/secrets/google-oauth/client-id"))
  client_secret = trimspace(file("/var/run/secrets/google-oauth/client-secret"))
  scopes        = ["openid", "profile", "email"]

  is_linking_allowed  = true
  is_creation_allowed = true
  is_auto_creation    = true
  is_auto_update      = true
  # auto_linking doesn't exist on this resource at the pinned provider
  # v1.2.0 (confirmed against its docs/resources/org_idp_google.md) --
  # dropped, not renamed; presumably added in a later provider version.
}

# Creating the Google IDP above does NOT activate it -- Zitadel needs a
# login policy that explicitly lists it. Without this resource, Google
# Sign-In is fully configured but never appears on the login screen.
#
# Defaults chosen for this single-admin homelab; revisit if the threat
# model changes (e.g. adding more users):
#   - allow_register: false -- this org has exactly one intended user
#     (FirstInstance's human admin); no reason to let anyone self-register.
#   - force_mfa: false -- kept low-friction to match FirstInstance's
#     PasswordChangeRequired: false. Reconsider once WebAuthn/OTP is
#     actually set up for the admin account.
#   - ignore_unknown_usernames: true -- don't leak which usernames exist
#     on a failed login attempt.
#   - passwordless_type: ALLOWED (not forced) -- lets WebAuthn be used if
#     ever configured, without requiring it.
resource "zitadel_login_policy" "default" {
  org_id = local.org_id

  user_login         = true
  allow_register     = false
  allow_external_idp = true
  idps               = [zitadel_org_idp_google.default.id]

  force_mfa                = false
  force_mfa_local_only     = false
  passwordless_type        = "PASSWORDLESS_TYPE_ALLOWED"
  hide_password_reset      = false
  ignore_unknown_usernames = true

  default_redirect_uri = "https://id.hl.mkoelle.com/ui/console"

  password_check_lifetime       = "240h0m0s"
  external_login_check_lifetime = "240h0m0s"
  multi_factor_check_lifetime   = "24h0m0s"
  mfa_init_skip_lifetime        = "720h0m0s"
  second_factor_check_lifetime  = "24h0m0s"
}

# Zitadel generates both client_id and client_secret server-side on
# creation -- unlike Authelia, there's no way to pin client_id to a literal
# string like "argocd". Both are Read-Only/computed attributes. These
# Secrets are how ArgoCD/Grafana actually consume them: no Bitwarden
# round-trip, no risk of the two sides disagreeing.
resource "kubernetes_secret" "argocd_oidc" {
  metadata {
    name      = "zitadel-argocd-oidc-secret"
    namespace = "core-argocd"
  }
  data = {
    clientId     = zitadel_application_oidc.argocd.client_id
    clientSecret = zitadel_application_oidc.argocd.client_secret
  }
}

resource "kubernetes_secret" "grafana_oidc" {
  metadata {
    name      = "zitadel-grafana-oidc-secret"
    namespace = "monitoring"
  }
  data = {
    client-id     = zitadel_application_oidc.grafana.client_id
    client-secret = zitadel_application_oidc.grafana.client_secret
  }
}
