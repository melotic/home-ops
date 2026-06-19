terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.20"
    }
  }
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "account_id" {
  type = string
}

variable "allow_email" {
  type    = string
  default = "spike@melotic.dev"
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

resource "cloudflare_zero_trust_access_application" "verify" {
  account_id       = var.account_id
  name             = "tofu-verify"
  domain           = "tofu-verify.melotic.dev"
  type             = "self_hosted"
  session_duration = "1h"

  policies = [{
    id         = cloudflare_zero_trust_access_policy.verify_allow.id
    precedence = 1
  }]
}

resource "cloudflare_zero_trust_access_policy" "verify_allow" {
  account_id = var.account_id
  name       = "tofu-verify-allow"
  decision   = "allow"
  include = [{
    email = {
      email = var.allow_email
    }
  }]
}

output "app_id" {
  value = cloudflare_zero_trust_access_application.verify.id
}
