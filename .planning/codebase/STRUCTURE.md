# Codebase Structure

**Analysis Date:** 2026-04-24

## Directory Layout

```
home-ops/
├── .github/                         # GitHub workflows and CI configuration
│   ├── workflows/                   # GitHub Actions workflows
│   └── skills/                      # Project agent skills (if present)
├── .planning/                       # Planning artifacts (agent-generated)
│   └── codebase/                    # Codebase analysis docs
├── .taskfiles/                      # Modular Task taskfiles
│   ├── bootstrap/                   # Bootstrap-specific tasks
│   └── talos/                       # Talos-specific tasks
├── .mise.toml                       # Tool versioning (Python, kubectl, flux, etc.)
├── .renovaterc.json5                # Renovate config (dependency updates)
├── .sops.yaml                       # SOPS encryption rules and key references
├── bootstrap/                       # Pre-Flux bootstrapping
│   └── helmfile.d/                  # Helmfile charts for initial setup
├── kubernetes/                      # All Kubernetes manifests and GitOps config
│   ├── apps/                        # Application workloads organized by namespace
│   │   ├── cert-manager/            # TLS certificate management
│   │   ├── cnpg-system/             # CloudNativePG database system
│   │   ├── database/                # Database apps (Postgres instances)
│   │   ├── default/                 # User applications (Plex, Sonarr, Radarr, etc.)
│   │   ├── external-secrets/        # External Secrets operator
│   │   ├── flux-system/             # Flux itself (operator, instance)
│   │   ├── kube-system/             # Core Kubernetes system components
│   │   ├── longhorn-system/         # Storage provisioner (block storage)
│   │   ├── monitoring/              # Observability stack (Prometheus, Grafana, Loki)
│   │   ├── network/                 # Network services (DNS, gateway controllers)
│   │   ├── system-upgrade/          # System upgrade operators
│   │   └── volsync-system/          # Backup/restore orchestration
│   ├── components/                  # Reusable Kustomize components and shared config
│   │   ├── common/                  # Shared: namespace, repos, SOPS secrets
│   │   ├── alerts/                  # Alert routing templates
│   │   ├── authentik-proxy/         # Reverse proxy/auth component
│   │   └── volsync/                 # Backup/restore resource templates
│   └── flux/                        # Flux bootstrap and orchestration
│       ├── cluster/                 # Root Kustomizations (cluster-meta, cluster-apps)
│       └── meta/                    # Flux metadata (placeholder for future)
├── scripts/                         # Helper shell scripts
│   ├── bootstrap-apps.sh            # Bootstrap script: namespace/secrets/helm setup
│   └── lib/                         # Shared shell script utilities
├── talos/                           # Talos machine configuration
│   ├── talconfig.yaml               # Talos cluster + node declarations
│   ├── talenv.yaml                  # Talos and Kubernetes version pins (Renovate-managed)
│   ├── talsecret.sops.yaml          # Encrypted Talos cluster secrets
│   ├── clusterconfig/               # Generated Talos configs (machine configs per node)
│   └── patches/                     # Talos configuration patches
│       ├── global/                  # Applied to all nodes
│       └── controller/              # Applied to control-plane nodes
├── .gitignore                       # Git exclusions (age.key, kubeconfig, node outputs, etc.)
├── .sops.yaml                       # SOPS encryption policy
├── Taskfile.yaml                    # Root Task orchestration
├── cluster.sample.yaml              # Template for user cluster.yaml config
├── nodes.sample.yaml                # Template for user nodes.yaml config
├── age.key                          # Age encryption private key (must not commit)
├── kubeconfig                       # Kubernetes config (must not commit; generated)
├── LICENSE                          # License file
└── README.md                        # Project overview and bootstrap instructions
```

## Directory Purposes

**`.planning/codebase/`:**
- Purpose: Agent-generated codebase analysis documents (ARCHITECTURE.md, STRUCTURE.md, etc.)
- Contains: Markdown analysis files following GSD conventions
- Key files: All documents are analysis only; read-only

**`kubernetes/apps/`:**
- Purpose: Namespace-organized application workloads and platform components
- Contains: Per-app directories with HelmRelease, OCI repositories, Kustomizations, secrets
- Key files: 
  - `{app}/ks.yaml`: Flux Kustomization declaring the app (with dependencies, substitutions)
  - `{app}/app/helmrelease.yaml`: Helm chart deployment declarative spec
  - `{app}/app/ocirepository.yaml`: OCI registry reference for the chart
  - `{app}/app/kustomization.yaml`: Kustomize resources list (helmrelease, secrets, extra manifests)
  - `{app}/app/*.sops.yaml`: Encrypted secrets per app (e.g., API keys, DB passwords)

**`kubernetes/components/common/`:**
- Purpose: Shared foundational configuration (namespaces, repos, SOPS secrets)
- Contains: Kustomize Component with namespace.yaml, repos/, sops/ subdirs
- Key files:
  - `namespace.yaml`: Creates flux-system namespace (required for Flux)
  - `repos/kustomization.yaml`: GitRepository and HelmRepository CRDs (placeholder for future)
  - `sops/sops-age.sops.yaml`: Encrypted age key for Flux decryption in cluster
  - `sops/cluster-secrets.sops.yaml`: Cluster-wide encrypted secrets

**`kubernetes/components/volsync/`:**
- Purpose: Backup/restore (volsync) configuration templates for apps using persistent volumes
- Contains: ResourceClaimTemplate and volsync policy definitions
- Key files: Shared by apps via `components: [../../../../components/volsync]` in their Kustomizations

**`kubernetes/flux/cluster/`:**
- Purpose: Root orchestration; entry point for Flux reconciliation
- Contains: Two root Kustomizations that define bootstrap and app deployment order
- Key files:
  - `ks.yaml`: Defines `cluster-meta` (foundational resources) and `cluster-apps` (all apps); applies patches to all child HelmReleases

**`talos/`:**
- Purpose: Machine configuration as code for Talos Linux nodes
- Contains: Declarative cluster/node specs, patches, encrypted secrets, generated outputs
- Key files:
  - `talconfig.yaml`: Human-written; declares nodes, Talos/K8s versions, CNI (none for Cilium), system extensions
  - `talenv.yaml`: Version pins (Renovate-managed to auto-update)
  - `talsecret.sops.yaml`: Encrypted etcd secrets, CA certs (generated by talhelper, committed SOPS-encrypted)
  - `clusterconfig/`: Generated per-node machine configs (*.yaml files generated, not human-written)
  - `patches/global/`: Global overrides (e.g., network, kubelet, time, API, sysctls)
  - `patches/controller/`: Control-plane-only overrides (e.g., admission controller)

**`scripts/`:**
- Purpose: Imperative helper scripts for bootstrap and operations
- Contains: Bash scripts with sourced common.sh for logging
- Key files:
  - `bootstrap-apps.sh`: Waits for nodes → applies namespaces → applies SOPS secrets → applies helmfile → Flux takes over
  - `lib/common.sh`: Logging functions (log debug, info, error)

**`bootstrap/helmfile.d/`:**
- Purpose: Pre-Flux Helm charts for initial cluster setup (core platform components before Flux)
- Contains: Helmfile definitions (YAML listing charts to deploy before Flux)
- When used: Only during `task bootstrap:apps`; Flux manages these post-bootstrap

**`.taskfiles/`:**
- Purpose: Modular Task orchestration (separate from root Taskfile.yaml)
- Contains: Namespace-specific task definitions (bootstrap, talos)
- Key files:
  - `bootstrap/Taskfile.yaml`: `task bootstrap:talos` and `task bootstrap:apps` definitions
  - `talos/Taskfile.yaml`: Talos operations (generate-config, apply-node, upgrade-node, upgrade-k8s, reset)

## Key File Locations

**Entry Points:**

- `Taskfile.yaml`: Root task orchestration; commands: `task reconcile`, `task bootstrap:talos`, `task bootstrap:apps`, `task talos:*`
- `kubernetes/flux/cluster/ks.yaml`: Flux root Kustomization; applied after cluster bootstrap; reconciles all apps
- `.taskfiles/bootstrap/Taskfile.yaml`: Bootstrap tasks entry; calls talhelper, talosctl, and bootstrap-apps.sh
- `scripts/bootstrap-apps.sh`: Bash entry point for post-Talos app setup; waits for API, applies namespaces/secrets/Helm

**Configuration:**

- `talos/talconfig.yaml`: Talos cluster and node configuration (human-written; version-controlled)
- `talos/talenv.yaml`: Version pins for Talos and Kubernetes (Renovate-managed)
- `.mise.toml`: Tool versions (Python, kubectl, flux, helm, talosctl, etc.)
- `.sops.yaml`: SOPS/age encryption policy (defines which files are encrypted and with which key)
- `.renovaterc.json5`: Renovate bot configuration (auto-update versions in talenv.yaml, .mise.toml)

**Core Logic:**

- `kubernetes/flux/cluster/ks.yaml`: Defines dependency DAG: cluster-meta → cluster-apps (all namespace apps)
- `kubernetes/apps/{namespace}/{app}/ks.yaml`: Kustomization per app; declares dependencies (e.g., longhorn, cnpg), substitutions, components
- `kubernetes/apps/{namespace}/{app}/app/helmrelease.yaml`: HelmRelease manifests (chart, values, install/upgrade/rollback strategies)

**Platform Components:**

- `kubernetes/apps/cert-manager/`: TLS certificate provisioning (wildcard certs via ACME)
- `kubernetes/apps/kube-system/`: CoreDNS, Cilium CNI, system components
- `kubernetes/apps/flux-system/`: Flux operator and Flux instance (reconciliation engine)
- `kubernetes/apps/external-secrets/`: External Secrets operator (pulls secrets from 1Password)
- `kubernetes/apps/longhorn-system/`: Block storage provisioner
- `kubernetes/apps/monitoring/`: kube-prometheus-stack, Grafana, Loki, Gatus

**Secrets & Encryption:**

- `age.key`: Age private key (local, .gitignored; NEVER commit)
- `kubernetes/components/common/sops/sops-age.sops.yaml`: Age key encrypted as Kubernetes Secret (Flux decryption)
- `talos/talsecret.sops.yaml`: Encrypted Talos secrets (etcd key, CA certs)
- `kubernetes/**/*.sops.yaml`: Encrypted app secrets (API keys, DB passwords, etc.)
- `.sops.yaml`: Defines encryption rules (age public key, which files are encrypted)

## Naming Conventions

**Files:**

- Kustomizations: `ks.yaml` (Flux Kustomization CRD)
- Kustomize manifests: `kustomization.yaml` (Kustomize manifest, not Flux)
- Helm releases: `helmrelease.yaml` (singular, matching spec metadata.name)
- OCI repositories: `ocirepository.yaml` (singular, chart source)
- Encrypted YAML: `*.sops.yaml` (suffix indicates SOPS-encrypted; file is valid YAML but with encrypted fields)
- Patches: `*.yaml` in `patches/` directories (applied by talhelper or Kustomize overlay)
- Secrets: `*secret*.yaml` or `secret.sops.yaml` (match application or generic)

**Directories:**

- Namespace names: lowercase, match Kubernetes namespace (e.g., `default`, `monitoring`, `flux-system`, `kube-system`)
- App names: lowercase, hyphen-separated (e.g., `home-assistant`, `cert-manager`, `external-secrets`)
- Talos patches: `global/` (all nodes), `controller/` (control-plane), `worker/` (worker nodes, if present)
- Platform layer: `components/` (reusable), `flux/` (orchestration), `apps/` (workloads)

**Variables (Kustomize postBuild substitutions):**

- Format: `${VAR_NAME}` in kustomization.yaml spec.postBuild.substitute
- Examples: `${APP}` (app name), `${VOLSYNC_CAPACITY}` (backup volume size), `${VOLSYNC_PUID}` (user ID for volsync)
- Convention: UPPERCASE, matching the purpose (e.g., VOLSYNC_PUID for pod user ID)

## Where to Add New Code

**New Application Workload:**

1. **Primary code location**: `kubernetes/apps/{namespace}/{app}/`
   - If namespace doesn't exist, create it under `kubernetes/apps/`
   - Example namespace: `kubernetes/apps/default/` for user apps, `kubernetes/apps/monitoring/` for observability

2. **Structure per app**:
   ```
   kubernetes/apps/{namespace}/{app}/
   ├── ks.yaml                       # Flux Kustomization (declares dependencies, substitutions)
   └── app/
       ├── kustomization.yaml        # Kustomize manifest listing resources
       ├── helmrelease.yaml           # HelmRelease CRD (chart deployment)
       ├── ocirepository.yaml         # OCIRepository CRD (chart source)
       ├── *.sops.yaml                # Encrypted secrets (API keys, etc.)
       └── [other resources.yaml]     # Extra manifests (ingress, networkpolicy, etc.)
   ```

3. **Tests**: No dedicated test directory; validation is GitOps-based (Flux reconciles and alerts on failures)

4. **Configuration**: Use HelmRelease `.spec.values` for chart configuration; External Secrets for sensitive values

**New Platform Component:**

1. **Primary code location**: `kubernetes/apps/{platform-namespace}/`
   - System components go in dedicated namespaces (e.g., `cert-manager`, `kube-system`, `longhorn-system`)
   - Follow same structure as workload apps

2. **Reusable shared logic**: 
   - If used by multiple apps, create a Component under `kubernetes/components/{name}/`
   - Example: `kubernetes/components/volsync/` (referenced by apps with persistent volumes)

**New Talos Node Configuration:**

1. **Primary code location**: `talos/talconfig.yaml`
   - Add node entry under `nodes:` section with hostname, IP, network config, system extensions
   - Example from existing: hostname `k8s-trinity`, IP `10.60.85.11`, secure boot, Intel extensions

2. **Node-specific patches** (if needed):
   - Create directory `talos/patches/nodes/{hostname}/` 
   - Add YAML patch files (though most use global/controller patches)
   - Patches applied by talhelper during `genconfig`

3. **Generate and apply**:
   - `task talos:generate-config` (runs talhelper, outputs to `clusterconfig/`)
   - `task talos:apply-node IP=10.60.85.10` (applies to single node)

**New Bootstrap Task:**

1. **Primary code location**: `.taskfiles/bootstrap/Taskfile.yaml` or `.taskfiles/talos/Taskfile.yaml`
   - Add task under `tasks:` section with `desc:`, `cmd:`, `preconditions:`, `vars:`
   - Include logging via `log info/error` for transparency

2. **Shared functions**:
   - Add bash functions to `scripts/lib/common.sh` if used across scripts
   - Existing functions: `log debug`, `log info`, `log error`, `wait_for_nodes`, `apply_namespaces`, `apply_sops_secrets`

**New Encrypted Secret:**

1. **Primary code location**:
   - App secret: `kubernetes/apps/{namespace}/{app}/app/{secret-name}.sops.yaml`
   - Cluster secret: `kubernetes/components/common/sops/cluster-secrets.sops.yaml`

2. **Encryption policy**: Already defined in `.sops.yaml`; all `*.sops.yaml` files encrypted with age key at `age.key`

3. **Workflow**:
   - Create plaintext YAML with secret structure
   - Run `sops --filename-override kubernetes/{path}/{file}.sops.yaml --encrypt {file}.yaml`
   - Commit encrypted `{file}.sops.yaml`; .gitignore prevents plaintext leak

## Special Directories

**`.planning/codebase/`:**
- Purpose: Agent-generated analysis documents
- Generated: Yes (by /gsd-map-codebase agent)
- Committed: Yes (version-controlled for reference)
- Files are read-only reference; do not edit manually

**`kubernetes/flux/cluster/` and `kubernetes/flux/meta/`:**
- Purpose: Flux bootstrap and metadata
- Generated: No (human-written)
- Committed: Yes
- `ks.yaml` defines the reconciliation DAG; `meta/kustomization.yaml` is a placeholder

**`talos/clusterconfig/`:**
- Purpose: Generated Talos machine configurations (per-node outputs)
- Generated: Yes (by talhelper genconfig)
- Committed: Yes (version-controlled for reproducibility)
- Files: `kubernetes-{hostname}.yaml` per node, plus `talosconfig` (kubeconfig for Talos API)

**`bootstrap/helmfile.d/`:**
- Purpose: Pre-Flux Helm charts
- Generated: No (human-written or templated)
- Committed: Yes
- Only used during initial bootstrap; Flux manages these post-bootstrap

**`age.key`:**
- Purpose: Age encryption private key
- Generated: Yes (by talhelper gensecret; first time only)
- Committed: No (.gitignored)
- Must be backed up securely; loss makes encrypted files unrecoverable

---

*Structure analysis: 2026-04-24*
