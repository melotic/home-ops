terraform {
  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.29"
    }
  }
}

provider "tailscale" {
  oauth_client_id     = var.oauth_client_id
  oauth_client_secret = var.oauth_client_secret
}

# Owns the ENTIRE tailnet policy file. The policy lives in policy.hujson
# (HuJSON: comments + trailing commas preserved, readable PR diffs).
# reset_acl_on_destroy=false so a destroy never reverts the tailnet to the
# permit-all default. overwrite_existing_content=true to adopt the existing
# console-managed policy without a manual import step.
resource "tailscale_acl" "policy" {
  acl                        = file("${path.module}/policy.hujson")
  overwrite_existing_content = true
  reset_acl_on_destroy       = false
}
