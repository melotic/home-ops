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

# Split DNS: resolve every *.melotic.dev query from a tailnet device using the
# UniFi resolver (10.60.0.1) reached over the WireGuard subnet route.
#
# unifi-dns publishes records for BOTH gateways into the UDM with no
# gateway-name filter, so internal services resolve to 10.60.88.1
# (envoy-internal) and public services to 10.60.80.1 (envoy-external). The
# ts-srv-zion Connector advertises 10.60.0.0/16, which covers 10.60.0.1 and
# both LB IPs. An off-LAN device with Tailscale up therefore resolves and
# reaches any melotic.dev service by name, identical to being on the LAN.
#
# This is a restricted (per-domain) nameserver, so it is authoritative for
# melotic.dev whenever MagicDNS is on and does not touch global DNS, the
# policy file, or on-LAN/public paths.
resource "tailscale_dns_split_nameservers" "melotic_dev" {
  domain      = "melotic.dev"
  nameservers = ["10.60.0.1"]
}
