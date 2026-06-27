terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Identity provider 1: generic OIDC pointed at Authentik. CF reads the groups
# claim from the JWKS-verified id_token; the JWKS URL is per-application-slug.
resource "cloudflare_zero_trust_access_identity_provider" "authentik" {
  account_id = var.account_id
  name       = "Authentik (ZTNA)"
  type       = "oidc"
  config = {
    client_id     = var.oidc_client_id
    client_secret = var.oidc_client_secret
    auth_url      = "https://sso.melotic.dev/application/o/authorize/"
    token_url     = "https://sso.melotic.dev/application/o/token/"
    certs_url     = "https://sso.melotic.dev/application/o/cloudflare-access/jwks/"
    scopes        = ["openid", "email", "profile", "groups"]
    claims        = ["groups"]
    pkce_enabled  = true
  }
}

# Identity provider 2: One-time PIN break-glass. Carries no groups claim, so it
# is authorized via the operator-email rule on the policy below.
resource "cloudflare_zero_trust_access_identity_provider" "otp" {
  account_id = var.account_id
  name       = "One-time PIN"
  type       = "onetimepin"
  config     = {}
}

# Self-hosted Access application for the searxng canary. Both identity providers
# are allowed; auto_redirect_to_identity must stay false so the One-time PIN
# option is selectable when more than one provider is offered.
resource "cloudflare_zero_trust_access_application" "searxng" {
  account_id       = var.account_id
  name             = "searxng"
  domain           = "searxng.melotic.dev"
  type             = "self_hosted"
  session_duration = "24h"
  allowed_idps = [
    cloudflare_zero_trust_access_identity_provider.authentik.id,
    cloudflare_zero_trust_access_identity_provider.otp.id,
  ]
  auto_redirect_to_identity = false
  policies = [{
    id         = cloudflare_zero_trust_access_policy.ztna_users.id
    precedence = 1
  }]
}

# Shared, reusable allow policy for the ZTNA front door. Attach it to any Access
# application that should be gated on Authentik group membership: the primary
# rule matches the ztna-users group from the Authentik OIDC id_token, and the
# operator-email rule is a One-time PIN break-glass path (One-time PIN identities
# carry no groups claim) available to every app that references this policy.
resource "cloudflare_zero_trust_access_policy" "ztna_users" {
  account_id = var.account_id
  name       = "allow-ztna-users"
  decision   = "allow"
  include = [
    {
      oidc = {
        identity_provider_id = cloudflare_zero_trust_access_identity_provider.authentik.id
        claim_name           = "groups"
        claim_value          = "ztna-users"
      }
    },
    {
      email = {
        email = var.operator_email
      }
    },
  ]
}

# The policy was renamed from searxng_allow; preserve its identity so the rename
# is an in-place update instead of a destroy and recreate.
moved {
  from = cloudflare_zero_trust_access_policy.searxng_allow
  to   = cloudflare_zero_trust_access_policy.ztna_users
}

output "authentik_idp_id" {
  value = cloudflare_zero_trust_access_identity_provider.authentik.id
}
