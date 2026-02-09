# Authentik Blueprints

This directory contains Authentik blueprints that configure OAuth2/OIDC providers and applications as code.

## Overview

Blueprints are declarative YAML files that automate the configuration of Authentik resources. They are mounted into the Authentik pods via ConfigMaps and automatically applied on startup or when updated.

## Structure

- `configmap.yaml` - Kubernetes ConfigMap containing all blueprints
- `helmrelease.yaml` - Authentik Helm release configured to use blueprints

## Applications Configured

### Grafana
- OAuth2 Provider with OIDC support
- Application entry in Authentik
- Groups: `grafana-admins`, `grafana-editors`

### Harbor
- OAuth2 Provider with OIDC support
- Application entry in Authentik
- Groups: `harbor-admins`

### Forejo
- OAuth2 Provider with OIDC support
- Application entry in Authentik
- Groups: `forejo-admins`

## Secrets

Client IDs and secrets are stored in 1Password and injected via External Secrets Operator. The following keys must exist in 1Password:

### Required 1Password Setup

Before deploying, ensure the following vaults/items exist in 1Password:

- **grafana** vault/item:
  - `oauth_client_id` - Generate a random client ID or use a meaningful identifier
  - `oauth_client_secret` - Generate a secure random secret (e.g., using `openssl rand -base64 32`)

- **harbor** vault/item:
  - `oauth_client_id` - Generate a random client ID or use a meaningful identifier
  - `oauth_client_secret` - Generate a secure random secret (e.g., using `openssl rand -base64 32`)

- **forejo** vault/item:
  - `oauth_client_id` - Generate a random client ID or use a meaningful identifier
  - `oauth_client_secret` - Generate a secure random secret (e.g., using `openssl rand -base64 32`)

**Note**: The client IDs and secrets can be any secure random strings. They will be used by Authentik to configure the OAuth2 providers and by the applications to authenticate with Authentik.

## How It Works

1. The `configmap.yaml` contains all blueprint YAML files as data keys
2. The HelmRelease mounts this ConfigMap via `blueprints.configMaps`
3. Authentik reads blueprints from `/blueprints/mounted/` on startup
4. Environment variables (client IDs/secrets, SECRET_DOMAIN) are templated using Jinja2
5. Resources are created or updated idempotently

## Adding New Applications

To add a new application:

1. Add a new blueprint section to `configmap.yaml`:
   ```yaml
   myapp.yaml: |
     ---
     version: 1
     metadata:
       name: MyApp OAuth2 Provider and Application
     entries:
       - model: authentik_providers_oauth2.oauth2provider
         # ... provider config
       - model: authentik_core.application
         # ... application config
   ```
2. Add the client ID/secret to the External Secret:
   - Store credentials in 1Password under a vault named `myapp`
   - Update `externalsecret.yaml` to extract these values

3. The blueprint will be automatically applied on the next Authentik pod restart

## References

- [Authentik Blueprints Documentation](https://docs.goauthentik.io/customize/blueprints/)
- [Blueprint File Structure](https://docs.goauthentik.io/customize/blueprints/v1/structure/)
- [Blueprint Models](https://docs.goauthentik.io/customize/blueprints/v1/models/)
