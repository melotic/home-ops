# External Integrations

**Analysis Date:** 2026-04-24

## APIs & External Services

**Cloudflare (DNS & Tunneling):**
- Service: Cloudflare DNS API
  - SDK/Client: `cloudflared` v2026.3.0
  - Auth: API token in Cloudflare DNS secret (`cloudflare-dns-secret`)
  - Config: `kubernetes/apps/network/cloudflare-dns/`
  - External DNS provider: `provider: cloudflare`

- Service: Cloudflare Tunnel
  - SDK/Client: `cloudflared` v2026.3.0
  - Usage: Public ingress via Kubernetes Gateway
  - Credentials: `cloudflare-tunnel.json` (from `cloudflared tunnel login`)
  - Config: `kubernetes/apps/network/cloudflare-tunnel/`

- Service: Cloudflare Turnstile CAPTCHA
  - Usage: Authentik login flow MFA enforcement
  - JS endpoint: `https://challenges.cloudflare.com/turnstile/v0/api.js`
  - Verify endpoint: `https://challenges.cloudflare.com/turnstile/v0/siteverify`
  - Config: `kubernetes/apps/default/authentik/app/blueprints/flow-login.yaml`

**Let's Encrypt:**
- Service: ACME certificate provisioning
  - Provider: Let's Encrypt
  - Challenge method: DNS (via Cloudflare)
  - Configuration: `kubernetes/apps/cert-manager/cert-manager/app/clusterissuer.yaml`
  - Wildcard certs generated via cert-manager

**1Password:**
- Service: Secrets vault and External Secrets backend
  - SDK/Client: 1Password Connect Operator v2.4.1
    - Helm: `oci://ghcr.io/1password/connect`
    - Containers: `ghcr.io/1password/connect-api`, `ghcr.io/1password/connect-sync`
  - Config: `kubernetes/apps/external-secrets/onepassword/`
  - Credentials: Encrypted 1Password service account JSON
  - Network policies: Allow outbound to `*.1password.com`, `*.1passwordservices.com`, `*.1passwordusercontent.com`
  - Secrets source: ClusterSecretStore named `onepassword`

**UniFi:**
- Service: Home network DNS & monitoring
  - Integration: UniFi DNS resolver (split-DNS for home network)
  - Monitoring: Unpoller exports UniFi metrics
  - Config: `kubernetes/apps/network/unifi-dns/`

**GitHub:**
- Service: Repository hosting and Actions CI/CD
  - SDK/Client: `gh` CLI v2.91.0
  - Config: `.github/workflows/` directory
  - Workflows:
    - `flux-local.yaml` - Local Flux validation
    - `labeler.yaml` - PR labeling automation
    - `label-sync.yaml` - Label synchronization
  - Renovate integration: Automated dependency updates via Renovate bot

## Data Storage

**Databases:**
- PostgreSQL via CloudNativePG (CNPG)
  - Connection: `postgres-cluster-rw.database:5432`
  - Operator: CloudNativePG v0.28.0
  - Cluster: `postgres-cluster` (3-instance HA setup)
  - Databases:
    - `harbor` (container registry)
    - `forejo` (Forgejo git)
    - `paperless` (document management)
  - Credentials: External Secrets from 1Password (`postgres-cluster-app`)
  - Backup: Barman Cloud to Azure Blob Storage
  - Config: `kubernetes/apps/database/postgres/`

- Dragonfly (In-memory data store)
  - Image: `docker.dragonflydb.io/dragonflydb/dragonfly:v1.38.0`
  - Use case: Session store, caching
  - Memory limit: 512MB
  - Config: `kubernetes/apps/database/dragonfly/`

**File Storage:**
- Longhorn (Distributed block storage)
  - Provisioner: `driver.longhorn.io`
  - Storage classes:
    - `longhorn` (default, general purpose)
    - `longhorn-cnpg-strict-local` (PostgreSQL, strict local)
  - Backup target: CIFS at `cifs://construct.melotic.dev/backups/longhorn`
  - Credentials: CIFS credentials from 1Password (`construct` secret)
  - Recurring jobs:
    - Snapshots every 6h (retain 4)
    - Weekly filesystem trim
    - Snapshot cleanup 4x daily
  - Config: `kubernetes/apps/longhorn-system/`

- NFS (Network File System)
  - Support: `siderolabs/nfs-utils` system extension on Talos nodes
  - CSI driver: `csi-driver-nfs` for persistent volume claims

- Azure Blob Storage
  - Service: Cloud backup for CloudNativePG
  - Account: `homeopsbackup.blob.core.windows.net`
  - Container: `cnpg-backup`
  - Credentials: External Secrets from 1Password (`cnpg-backup-azure`)
  - Compression: Data (snappy), WAL (zstd)

**Caching:**
- No dedicated cache service (Dragonfly provides in-memory store)
- Cilium pod-to-pod L4 policy caching

## Authentication & Identity

**Auth Provider:**
- Authentik (Self-hosted identity provider)
  - Helm: Multiple releases (main app + outpost)
  - Config: `kubernetes/apps/default/authentik/`
  - Database: PostgreSQL (`postgres-cluster`)
  - Storage: Longhorn persistent volume
  - Features:
    - OIDC/OAuth2 provider
    - SAML support
    - MFA with Cloudflare Turnstile
    - GeoIP restriction support
    - Application outpost for Kubernetes workloads
  - Blueprints: Pre-configured integrations for Grafana, Harbor, Longhorn, Victoria, SearXNG, etc.
  - Authentication: External Secrets from 1Password

**Internal Access Control:**
- Kubernetes RBAC (Kubernetes native)
- Cilium network policies (pod-to-pod L3/L4 policies)

**TLS/mTLS:**
- cert-manager with Cloudflare DNS challenge
- Kubernetes certificate API for inter-component TLS

## Monitoring & Observability

**Error Tracking:**
- Grafana + Prometheus (Victoria Metrics backend)
  - Alertmanager for alert routing
  - PrometheusRules for alert definitions
  - Config: `kubernetes/apps/monitoring/`

**Logs:**
- Loki + Fluent-bit pipeline
  - Fluent-bit: Collects logs from all pods
  - Loki: Log aggregation backend
  - Config: `kubernetes/apps/monitoring/fluent-bit/`

**Metrics:**
- Victoria Metrics K8s Stack v0.74.1
  - Prometheus-compatible scraping
  - Victoria Metrics: Time-series storage
  - Victoria Logs: Log backend
  - Grafana: Visualization
  - Config: `kubernetes/apps/monitoring/victoria-metrics-k8s-stack/`

**Health & Status:**
- Gatus: Endpoint health monitoring
  - Config: `kubernetes/apps/monitoring/gatus/`
  - Dashboard: Health status UI

**Infrastructure Monitoring:**
- Unpoller: UniFi network controller metrics
  - Config: `kubernetes/apps/monitoring/unpoller/`
  - Scrapes UniFi API for network/device metrics

- SmartCTL Exporter: Disk health monitoring
  - Config: `kubernetes/apps/monitoring/smartctl-exporter/`

- Kromgo: Metrics dashboard display
  - External service: `https://kromgo.melotic.dev`
  - Displays cluster stats (version, node count, uptime, etc.)

**Dashboard Infrastructure:**
- Grafana
  - Config: `kubernetes/apps/monitoring/grafana/`
  - Authentication: Authentik
  - Data sources: Prometheus (Victoria Metrics), Loki, Mimir

## CI/CD & Deployment

**Hosting:**
- Talos Kubernetes cluster on bare metal
- Cluster nodes: 3x control plane (k8s-niobe, k8s-trinity, k8s-ghost)

**CI Pipeline:**
- GitHub Actions (Renovate bot integration)
  - Automated dependency updates (Helm charts, Docker images, GitHub releases)
  - Schedule: Weekly
  - Auto-merge: Enabled for minor/patch updates
  - Config: `.renovaterc.json5`

**Deployment:**
- FluxCD v2.8.6 for GitOps reconciliation
  - Source: Git repository (self-hosted via Forgejo)
  - Reconciliation: Kustomization and HelmRelease resources
  - Config validation: Flux schema validation + kubeconform
  - Secret decryption: SOPS (age encryption)

**Image Distribution:**
- Spegel v0.7.0: P2P OCI image distribution
- Container registries:
  - Harbor (local, self-hosted)
  - GHCR (GitHub Container Registry)
  - Quay.io
  - Docker Hub (Dragonflydb)

## Environment Configuration

**Required env vars (set by Mise):**
- KUBECONFIG: Path to kubeconfig file
- SOPS_AGE_KEY_FILE: Path to age encryption key
- TALOSCONFIG: Path to Talos config
- Custom per-task vars in `.mise.toml` [env] section

**Secrets location:**
- SOPS-encrypted files: `.sops.yaml` configuration
  - Talos secrets: `talos/talsecret.sops.yaml`
  - Kubernetes secrets: `kubernetes/**/*.sops.yaml`, `bootstrap/**/*.sops.yaml`
- 1Password vault: External Secrets integration
- Age encryption key: `age.key` (committed, public key only)

**Renovate Configuration:**
- `.renovaterc.json5` controls dependency updates
- Monitors:
  - Helm charts via FluxCD manager
  - OCI images via Docker manager
  - GitHub releases
  - Mise tools
- Custom managers for annotated dependencies in `.yaml`, `.sh`, `.env` files

## Webhooks & Callbacks

**Incoming Webhooks:**
- Cloudflare Tunnel: Public routes via external gateway
- GitHub: PR/push webhooks trigger Renovate updates
- Authentik webhooks: Application proxy integrations

**Outgoing Webhooks:**
- FluxCD: Reconciliation notifications (if configured)
- Alertmanager: Alert notifications (integration configurable)
- Renovate: PR creation and auto-merge notifications

**Gateway APIs:**
- Envoy Gateway v1 (Kubernetes Gateway API v1)
  - External gateway: Public routes via Cloudflare Tunnel
  - Internal gateway: Cluster-internal routing
  - Config: `kubernetes/apps/network/envoy-gateway/`

## Service Mesh & Network Policies

**CNI:**
- Cilium v1.18.6 (replaces Kubernetes default CNI)
  - L3/L4 network policies
  - Hubble for network observability
  - Config: Installed via helmfile bootstrap

**Network Policies:**
- CiliumNetworkPolicy resources per application
- 1Password: Restricted DNS egress to 1Password domains only
- Longhorn: Authorization via Authentik proxy

## Container Image Management

**Image Registries:**
- Private: Harbor (`harbor.melotic.dev`)
- Public: GHCR, Quay.io, Docker Hub
- Image pull via Spegel P2P distribution
- OCI image repositories: `ociRepository` resources for chart sources

## Data Backup & Disaster Recovery

**PostgreSQL Backups:**
- Method: Barman Cloud plugin (CloudNativePG)
- Destination: Azure Blob Storage (`homeopsbackup.blob.core.windows.net`)
- Schedule: Daily at 00:00 UTC
- Compression: Data (snappy), WAL (zstd)
- Retention: Configured via Barman Cloud plugin

**Longhorn Backups:**
- Destination: CIFS (`construct.melotic.dev/backups/longhorn`)
- Recurring snapshots every 6h (retain 4 copies)
- Trim operations: Weekly
- Backup target credentials: CIFS username/password from 1Password

**Dragonfly:**
- In-memory, no persistent backup (suitable for session data)

---

*Integration audit: 2026-04-24*
