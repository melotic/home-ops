# Technology Stack

**Analysis Date:** 2026-04-24

## Languages

**Primary:**
- YAML - Kubernetes manifests and configuration files
- Bash - Bootstrap and operational scripts in `scripts/`
- CUE - Templating via `aqua:cue-lang/cue` (0.16.1) for Kustomize and Helmfile values

**Secondary:**
- Python 3.14.4 - Mise environment and tooling
- Jinja2 - Template processing via `makejinja` (2.8.2) for `*.j2` files

## Runtime

**Environment:**
- Talos Linux v1.12.6 - Immutable OS for cluster nodes
- Kubernetes v1.36.0 - Container orchestration platform

**Package Manager:**
- Mise (version manager) - Primary tool orchestrator
  - Manages all CLI tools and Python environment
  - Configuration: `.mise.toml`
  - Python venv: `.venv/` (auto-created)

## Frameworks & Core Platform

**Cluster Infrastructure:**
- Talos Linux v1.12.6 (`aqua:siderolabs/talos` 1.12.6)
  - Machine configuration: `talos/talconfig.yaml`
  - 3-node control plane (k8s-niobe, k8s-trinity, k8s-ghost)
  - System extensions: amd-ucode, intel-ucode, amdgpu, nfs-utils, iscsi-tools, realtek-firmware
  - Virtual IP: 10.60.8.10

**GitOps & Reconciliation:**
- FluxCD v2.8.6 (`aqua:fluxcd/flux2`)
  - Kustomization resources for declarative GitOps
  - Bootstrap helmfile: `bootstrap/helmfile.d/`
  - Configuration: `kubernetes/flux/`

**Container Orchestration Tools:**
- kubectl 1.35.0 (`aqua:kubernetes/kubectl`)
- helm 4.1.4 (`aqua:helm/helm`)
- helmfile 1.4.4 (`aqua:helmfile/helmfile`)
- kustomize 5.7.1 (`aqua:kubernetes-sigs/kustomize`)
- talhelper 3.1.7 (`aqua:budimanjojo/talhelper`) - Talos config generation

**Task Automation:**
- Task v3.50.0 (`aqua:go-task/task`)
  - Main task file: `Taskfile.yaml`
  - Bootstrap tasks: `.taskfiles/bootstrap/`
  - Talos tasks: `.taskfiles/talos/`

## Key Dependencies

**Critical Infrastructure:**
- Cilium v1.18.6 - Container Network Interface (replaces built-in CNI)
  - Helm: `oci://ghcr.io/home-operations/charts-mirror/cilium`
  - Network policies via CiliumNetworkPolicy

- cert-manager v1.20.2 (`oci://quay.io/jetstack/charts/cert-manager`)
  - ACME certificate provisioning
  - Let's Encrypt integration with DNS challenge

- Flux Operator v0.48.0 + Flux Instance v0.48.0
  - Helm: `oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator`
  - Bootstrap orchestration

**Storage:**
- Longhorn v1.11.1 - Distributed block storage
  - Helm: `https://charts.longhorn.io`
  - Backup target: CIFS (construct.melotic.dev/backups/longhorn)
  - Storage class: `longhorn-cnpg-strict-local`

- CloudNativePG (CNPG) v0.28.0 - PostgreSQL operator
  - Helm: `https://cloudnative-pg.github.io/charts`
  - Barman Cloud plugin for backups to Azure Blob Storage

**Networking:**
- CoreDNS v1.45.2 - DNS server for in-cluster DNS
  - Helm: `oci://ghcr.io/coredns/charts/coredns`

- Envoy Gateway - Gateway API implementation
  - Replaces traditional Ingress with modern Gateway API
  - External and internal gateways configured

**Secrets & Encryption:**
- SOPS v3.12.2 (`aqua:getsops/sops`) - Secrets encryption
  - Age encryption: `aqua:FiloSottile/age` (1.3.1)
  - Configuration: `.sops.yaml`
  - Encrypted files: `kubernetes/**/*.sops.yaml`, `talos/**/*.sops.yaml`

- External Secrets Operator v2.3.0
  - Helm: `oci://ghcr.io/external-secrets/charts/external-secrets`
  - Sources secrets from 1Password

**Observability:**
- Victoria Metrics K8s Stack v0.74.1
  - Prometheus-compatible metrics collection
  - Helm: `oci://ghcr.io/victoriametrics/helm-charts/victoria-metrics-k8s-stack`

- kube-prometheus-stack - Prometheus, Grafana, Alertmanager
  - Configuration: `kubernetes/apps/monitoring/`

- Loki - Log aggregation
  - Fluent-bit for log forwarding

**Utilities:**
- Spegel v0.7.0 - OCI image distribution helper
  - Helm: `oci://ghcr.io/spegel-org/helm-charts/spegel`

- ReLoader - Automatic config reload for Pods
  - Watches ConfigMap/Secret changes

- Longhorn UI + Grafana - Visualization dashboards

**Development & Build Tools:**
- jq v1.8.1 (`aqua:jqlang/jq`) - JSON processor
- yq v4.53.2 (`aqua:mikefarah/yq`) - YAML processor
- kubeconform v0.7.0 (`aqua:yannh/kubeconform`) - Kubernetes manifest validation
- gh v2.91.0 (`aqua:cli/cli`) - GitHub CLI
- cilium-cli v0.19.2 (`aqua:cilium/cilium-cli`) - Cilium troubleshooting
- cloudflared v2026.3.0 (`aqua:cloudflare/cloudflared`) - Cloudflare Tunnel client

## Configuration

**Environment:**
- Managed via Mise: `.mise.toml`
  - KUBECONFIG: `{{config_root}}/kubeconfig`
  - SOPS_AGE_KEY_FILE: `{{config_root}}/age.key`
  - TALOSCONFIG: `{{config_root}}/talos/clusterconfig/talosconfig`

**Talos Configuration:**
- `talos/talconfig.yaml` - Declarative machine config
- `talos/talenv.yaml` - Talos-specific variables
- `talos/talsecret.sops.yaml` - Encrypted machine secrets
- Generated configs: `talos/clusterconfig/`

**Kubernetes Configuration:**
- `kubernetes/flux/` - FluxCD bootstrap
- `kubernetes/components/` - Shared resources (namespaces, repos, common config)
- `kubernetes/apps/` - Application deployments organized by namespace

**Build & Dependency Management:**
- `.renovaterc.json5` - Automated dependency updates via Renovate
  - Scans: Helm charts, Docker images, GitHub releases, Mise tools
  - Update schedule: Weekly

**Validation:**
- `.shellcheckrc` - Bash script linting

## Platform Requirements

**Development:**
- Bash 4.0+ (on macOS, requires upgrade via `brew install bash`)
- Git (for repository operations)
- Python 3.14.4 via Mise
- Pipx (installed via `pip install pipx`)
- Age encryption key file: `age.key`
- SOPS config: `.sops.yaml`

**Cluster Infrastructure:**
- 3+ nodes with Talos Linux v1.12.6
- Kubernetes 1.36.0+
- Control plane VIP: 10.60.8.10
- Cluster POD networks: 10.42.0.0/16, fd00:42::/48
- Service networks: 10.43.0.0/16, fd00:43::/112

**Storage Requirements:**
- Longhorn distributed storage (requires `/dev/nvme0n1` on nodes)
- CIFS backup target: `construct.melotic.dev/backups/longhorn`
- Azure Blob Storage: `homeopsbackup.blob.core.windows.net` (for CNPG backups)

---

*Stack analysis: 2026-04-24*
