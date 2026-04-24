# Architecture

**Analysis Date:** 2026-04-24

## Pattern Overview

**Overall:** GitOps-driven, multi-layer Infrastructure-as-Code with reconciliation-based deployment.

**Key Characteristics:**
- Declarative infrastructure and application definitions stored in Git
- Talos Linux for immutable, immutably-versioned machine configurations
- FluxCD as continuous reconciliation engine for Kubernetes manifests
- Layered configuration: machine layer (Talos) → Kubernetes cluster (via Talos) → applications (via Flux)
- Source-of-truth is Git; cluster state converges toward Git state through automated reconciliation
- Secrets encrypted at rest (SOPS with age encryption) and injected at runtime

## Layers

**Machine Layer (Talos):**
- Purpose: Immutable node OS configuration and Kubernetes cluster bootstrap
- Location: `talos/`
- Contains: Talos machine configuration patches, cluster configuration definitions, talenv/talconfig
- Depends on: talhelper for configuration generation, sops for secret encryption
- Used by: Bootstrap process to create initial cluster state

**Kubernetes Cluster Layer:**
- Purpose: Container orchestration runtime with core platform components
- Location: `kubernetes/flux/cluster/` and `kubernetes/flux/meta/`
- Contains: Flux Kustomization resources that orchestrate the cluster state
- Depends on: Git source (flux-system repository), SOPS secrets
- Used by: All applications and platform components

**Application Layer (Namespace-organized):**
- Purpose: User workloads and platform services grouped by operational domain
- Location: `kubernetes/apps/{namespace}/{app}/`
- Contains: HelmRelease definitions, OCI repositories, component references per app
- Depends on: Cluster-meta Kustomization for foundational resources
- Used by: End users and internal services

**Component/Shared Layer:**
- Purpose: Reusable Kustomize components and common configurations
- Location: `kubernetes/components/`
- Contains: Namespace definitions, repository credentials, SOPS configuration, shared patches
- Depends on: Nothing
- Used by: Applications and platform namespaces

**Bootstrap Layer (Pre-Flux):**
- Purpose: Initial cluster setup before Flux can take over reconciliation
- Location: `bootstrap/helmfile.d/`, `scripts/bootstrap-apps.sh`
- Contains: Helmfile charts for pre-Flux components, namespace bootstrapping scripts
- Depends on: talosctl, kubectl, helm, helmfile
- Used by: Initial cluster setup only

## Data Flow

**Cluster Bootstrap Flow:**

1. **Machine Configuration Phase**: `talos/talconfig.yaml` → talhelper generates per-node configs → talosctl applies to nodes
2. **Talos Nodes Ready**: Nodes boot with declarative machine config, form etcd cluster, start kubelet
3. **Kubernetes Bootstrap**: Bootstrap control-plane, API server, CoreDNS, Cilium CNI (no built-in CNI)
4. **Flux Installation**: `bootstrap-apps.sh` waits for nodes ready → applies namespaces → applies SOPS secrets → installs Flux via Helm
5. **Flux Reconciliation Begins**: `cluster-meta` Kustomization applies → `cluster-apps` Kustomization applies all apps

**Reconciliation Loop (Steady State):**

1. Flux controller polls Git repository (flux-system) for changes every 1h
2. For each Kustomization/HelmRelease, Flux compares current cluster state to desired Git state
3. If divergent, Flux reconciles: pulls chart, decrypts SOPS secrets, renders manifests, applies to cluster
4. Applications watch for ConfigMap/Secret changes (ReLoader annotations) and restart if secrets rotate
5. Conflict resolution: `prune: true` removes resources not in Git; `deletionPolicy: WaitForTermination` ensures graceful deletion

**State Management:**

- **Single Source of Truth**: Git repository
- **Desired State**: Kustomization + HelmRelease manifests in Git
- **Actual State**: Live Kubernetes cluster
- **Reconciliation**: Flux detects drift and converges actual → desired
- **Secrets**: Encrypted in Git (SOPS/age), decrypted only in cluster during Flux reconciliation

## Key Abstractions

**Kustomization (Flux-managed):**
- Purpose: Organize and recursively apply Kubernetes manifests with dependencies
- Examples: `kubernetes/flux/cluster/ks.yaml` (cluster-meta, cluster-apps), `kubernetes/apps/*/ks.yaml` (per-app)
- Pattern: Parent Kustomization depends on child Kustomizations; creates dependency DAG; prunes stale resources

**HelmRelease:**
- Purpose: Declarative Helm chart deployment with automatic upgrades and CRD handling
- Examples: `kubernetes/apps/default/plex/app/helmrelease.yaml`, `kubernetes/apps/cert-manager/cert-manager/app/helmrelease.yaml`
- Pattern: Chart sourced from OCIRepository; install/upgrade/rollback strategies defined; failures remediated via RemediateOnFailure

**OCIRepository:**
- Purpose: Reference to OCI-based Helm chart registry (ghcr.io)
- Examples: `kubernetes/apps/default/plex/app/ocirepository.yaml`
- Pattern: One OCIRepository per HelmRelease; Flux pulls chart metadata for version tracking

**Component (Kustomize):**
- Purpose: Reusable, composable Kustomize units without direct application
- Examples: `kubernetes/components/volsync/` (backup/restore template), `kubernetes/components/common/` (namespace, repos, SOPS)
- Pattern: Included via `components:` in app Kustomizations; applied before resources; namespace-scoped

**Talconfig + Talenv + Talsecret:**
- Purpose: Declarative Talos machine configuration with versioning
- Examples: `talos/talconfig.yaml` (cluster + node specs), `talos/talenv.yaml` (Talos/K8s versions), `talos/talsecret.sops.yaml` (encryption keys)
- Pattern: talhelper generates per-node configs; patches layer global + controller-specific overrides; sops encrypts secrets

## Entry Points

**Primary Reconciliation Entry Point:**
- Location: `kubernetes/flux/cluster/ks.yaml`
- Triggers: Flux controller detects Git commit; runs every 1h interval
- Responsibilities: Applies `cluster-meta` (foundational) → `cluster-apps` (all namespaced workloads); prunes stale; patches all child HelmReleases with defaults

**Manual Reconciliation Entry Point:**
- Location: Task `task reconcile` in `Taskfile.yaml`
- Triggers: Human command or CI
- Command: `flux --namespace flux-system reconcile kustomization flux-system --with-source`
- Responsibilities: Forces Flux to pull latest Git commit and reconcile immediately

**Bootstrap Entry Points:**
- Location: `task bootstrap:talos` → `.taskfiles/bootstrap/Taskfile.yaml::talos` task
- Triggers: Initial cluster setup
- Responsibilities: Generate Talos secrets (SOPS) → generate per-node configs → apply insecure → bootstrap API → fetch kubeconfig

- Location: `task bootstrap:apps` → `scripts/bootstrap-apps.sh`
- Triggers: After Talos nodes ready and API responding
- Responsibilities: Wait for nodes Ready=False → apply namespaces → apply SOPS secrets → apply helmfile (pre-Flux Helm) → Flux takes over

**Talos Operations Entry Points:**
- Location: `.taskfiles/talos/Taskfile.yaml`
- Tasks: `generate-config` (talhelper genconfig), `apply-node` (apply config to single node), `upgrade-node` (Talos upgrade), `upgrade-k8s` (control-plane K8s upgrade), `reset` (destructive reset)

## Error Handling

**Strategy:** Declarative reconciliation with automated remediation; manual intervention for severe failures.

**Patterns:**

- **Flux HelmRelease Remediation**: `remediation: {remediateLastFailure: true, retries: 2}` automatically retries failed upgrades up to 2 times
- **Rollback on Failure**: `rollback: {recreate: true, cleanupOnFail: true}` rolls back chart to previous version if upgrade fails
- **Dependency Ordering**: `dependsOn: [{name: parent, namespace: ns}]` ensures prerequisites (e.g., Longhorn PVC controller) before dependent app starts
- **Timeout Handling**: `timeout: 5m` terminates slow operations; retries after exponential backoff (`retryInterval: 2m`)
- **SOPS Decryption Failures**: If age key unavailable, Flux reconciliation blocks; cluster enters "not ready" state until secrets accessible
- **Image Pull Failures**: HelmRelease with `image.tag@sha256:hash` pins exact digest; failures trigger alert but no auto-retry (requires manual intervention)

## Cross-Cutting Concerns

**Logging:** No centralized logging in bootstrap; applications use standard container logging (captured by kubelet). Observability stack includes Loki for log aggregation post-bootstrap.

**Validation:** 
- SOPS files validated pre-commit via `.sops.yaml` rules (encryption_regex enforces encrypted fields)
- Kustomization schemas via YAML language-server directives (enable IDE validation)
- kubeconform validates manifests before application

**Authentication:**
- Machine-to-cluster: Talos generates kubeconfig; stored at `./kubeconfig` (local file)
- In-cluster: RBAC for Flux service account (full cluster admin in flux-system namespace); HelmRelease runs as chart's specified RBAC
- External: Cloudflare Tunnel for public ingress; UniFi DNS for internal split-DNS

**Encryption at Rest:**
- Talos secrets: `talos/talsecret.sops.yaml` (SOPS/age)
- Kubernetes secrets: `kubernetes/**/*.sops.yaml` (SOPS/age); Example: `kubernetes/components/common/sops/sops-age.sops.yaml` contains Flux decryption key
- Age private key: `./age.key` (must be kept secure; .gitignore excludes)

**Configuration Management:**
- Talos: talconfig patches layer global/controller/worker overrides (e.g., `talos/patches/global/machine-network.yaml`)
- Kustomize: postBuild substitutions inject per-app config (e.g., `VOLSYNC_CAPACITY: 50Gi` in plex app)
- Helm: values embedded in HelmRelease spec; External Secrets pulls 1Password data for sensitive configs

---

*Architecture analysis: 2026-04-24*
