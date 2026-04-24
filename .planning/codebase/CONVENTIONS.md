# Coding Conventions

**Analysis Date:** 2026-04-24

## YAML Structure and Formatting

**Schema Annotations (Required):**
Every YAML file must include a `yaml-language-server` schema annotation at the top for IDE validation and schema validation:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/helmrelease-helm-v2.json
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
```

Common schemas used:
- **Kustomization** (app-level): `https://json.schemastore.org/kustomization`
- **Kustomization** (Flux): `https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/kustomization-kustomize-v1.json`
- **HelmRelease**: `https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/helmrelease-helm-v2.json`
- **OCIRepository**: `https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/ocirepository-source-v1.json`
- **Secret**: `https://kubernetesjsonschema.dev/v1.18.1-standalone-strict/secret-v1.json`
- **ClusterIssuer**: `https://kubernetes-schemas.pages.dev/cert-manager.io/clusterissuer_v1.json`
- **PrometheusRule**: `https://kubernetes-schemas.pages.dev/monitoring.coreos.com/prometheusrule_v1.json`

**Indentation:**
- All YAML files: 2-space indentation (`.editorconfig`)
- `.cue` files: 4-space tabs
- Markdown files: 4-space indentation

**Line Endings:**
- LF (Unix line endings) across all files

**Trailing Whitespace:**
- Trim all trailing whitespace (except in markdown, where it is preserved for hard line breaks)

**File Requirements:**
- All files must end with a single newline character

Example from `.editorconfig`:
```
[*]
indent_style = space
indent_size = 2
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true
```

## Naming Conventions

**Kubernetes Resources:**
- Use kebab-case (lowercase with hyphens) for all resource names
- Example: `cert-manager`, `http-https-echo`, `external-secrets`
- Files: use kebab-case with `.yaml` extension
- Encrypted files: use `.sops.yaml` extension (e.g., `cert-manager-secret.sops.yaml`)

**HelmRelease Resources:**
- Metadata `name` matches the application name in kebab-case
- Example in `kubernetes/apps/cert-manager/cert-manager/app/helmrelease.yaml`:
  ```yaml
  metadata:
    name: cert-manager
  ```

**Namespaces:**
- Use kebab-case for namespace names (e.g., `cert-manager`, `kube-system`, `flux-system`)
- Define anchor at namespace level for reuse: `namespace: &namespace cert-manager`
- Kustomization resource names match their namespace

**YAML Anchors for DRY Configuration:**
Use YAML anchors (`&`) and aliases (`*`) to avoid duplication:

```yaml
metadata:
  name: &app cert-manager
  namespace: &namespace cert-manager
spec:
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  targetNamespace: *namespace
```

**Metadata Labels:**
- Flux Kustomizations apply `app.kubernetes.io/name: <app-name>` to all resources via `commonMetadata.labels`
- This is injected by the parent Kustomization pattern in `kubernetes/flux/cluster/ks.yaml`

## Directory Structure Conventions

**Application Layout** (`kubernetes/apps/<namespace>/<app-name>/`):
```
<app-name>/
  ks.yaml                   # Flux Kustomization (top-level, declares the app)
  app/
    kustomization.yaml      # Lists all resources in this directory
    helmrelease.yaml        # HelmRelease (main workload)
    ocirepository.yaml      # OCIRepository source for Helm chart
    externalsecret.yaml     # ExternalSecret (if secrets from 1Password)
    secret.sops.yaml        # SOPS-encrypted secrets (if any)
    other-resources.yaml    # Additional Kubernetes resources
```

**Top-level Kustomization Pattern** (`kubernetes/apps/<namespace>/kustomization.yaml`):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: <namespace>
components:
  - ../../components/alerts     # Include shared components if needed
  - ../../components/common     # For common repos/SOPS
resources:
  - ./app-one/ks.yaml
  - ./app-two/ks.yaml
```

**Shared Components** (`kubernetes/components/`):
- `common/`: Namespace definition, Helm repos, SOPS secrets
- `alerts/`: Alertmanager and GitHub status alert components
- `authentik-proxy/`: Authentik reverse proxy configuration
- `volsync/`: Restic backup configuration

## HelmRelease Conventions

**Chart Source (OCIRepository):**
Most applications use the `bjw-s-labs` app-template via OCI:

```yaml
# kubernetes/apps/<namespace>/<app>/app/ocirepository.yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/ocirepository-source-v1.json
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: <app>
spec:
  url: oci://ghcr.io/bjw-s-labs/helm/app-template
  ref:
    tag: <version>
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
```

**HelmRelease Configuration Pattern:**

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <app>
spec:
  interval: 1h
  chartRef:
    kind: OCIRepository
    name: <app>
  install:
    remediation:
      retries: -1
  upgrade:
    cleanupOnFail: true
    remediation:
      retries: 3
  dependsOn:
    - name: dependency-app
      namespace: dependency-namespace
  values:
    controllers:
      <app>:
        strategy: RollingUpdate
        containers:
          app:
            image:
              repository: ghcr.io/org/image
              tag: "1.0"
            env:
              VAR_NAME: &port 8080
            probes:
              liveness: &probes
                enabled: true
                custom: true
                spec:
                  httpGet:
                    path: /healthz
                    port: *port
              readiness: *probes
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities: { drop: ["ALL"] }
            resources:
              requests:
                cpu: 10m
              limits:
                memory: 64Mi
    defaultPodOptions:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
```

**Container Image Tagging:**
- Use explicit version tags (e.g., `tag: 40`, `tag: "1.2.3"`)
- Never use `latest`
- Leverage OCI digest pinning via Renovate for security

## Security Context Requirements

**Container-level Security Context (mandatory for all containers):**

```yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities: { drop: ["ALL"] }
```

**Pod-level Security Context:**

```yaml
defaultPodOptions:
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    fsGroupChangePolicy: OnRootMismatch
```

**Read-Only Filesystem Requirement:**
When `readOnlyRootFilesystem: true` is set, add a temporary volume:

```yaml
persistence:
  tmp:
    type: emptyDir
```

## Networking and Gateway API

**Ingress Pattern (Kubernetes Gateway API):**
Do NOT use Ingress resources. Use HTTPRoute via Gateway API instead.

Two gateways are available in the `network` namespace:
- `envoy-external` — publicly accessible via Cloudflare Tunnel
- `envoy-internal` — home network-only access

**HTTPRoute Example (in HelmRelease values):**

```yaml
route:
  app:
    hostnames: ["{{ .Release.Name }}.${SECRET_DOMAIN}"]
    parentRefs:
      - name: envoy-external      # or envoy-internal
        namespace: network
        sectionName: https
    rules:
      - backendRefs:
          - identifier: app
            port: 80
    annotations:
      gatus.home-operations.com/endpoint: |-
        conditions: ["[STATUS] == 200"]
```

**Variable Substitution:**
Use `${SECRET_DOMAIN}` for hostnames (substituted from `cluster-secrets` Secret during Flux reconciliation).

## Secrets Management

**SOPS Encryption Rules** (`.sops.yaml`):
- Files matching `talos/.*\.sops\.ya?ml` — encrypted entirely (file-level)
- Files matching `(bootstrap|kubernetes)/.*\.sops\.ya?ml` — only `data` and `stringData` fields encrypted
- All secrets use `age` encryption with a shared cluster key
- Indent: 2-space

**Encrypted Files:**
- Only the `data` or `stringData` fields are encrypted (metadata remains visible)
- Example:
  ```yaml
  # yaml-language-server: $schema=https://kubernetesjsonschema.dev/v1.18.1-standalone-strict/secret-v1.json
  apiVersion: v1
  kind: Secret
  metadata:
    name: my-secret
  stringData:
    key: ENC[AES256_GCM,...] # encrypted
  ```

**ExternalSecret Pattern (for 1Password integration):**

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: <app>
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword
  target:
    name: <app>-secret
    template:
      data:
        SOME_KEY: "{{ .SOME_VALUE }}"
  dataFrom:
    - extract:
        key: <vault-item-name>
```

**Secret Verification Before Commit:**
Verify encrypted status before pushing to avoid leaking plaintext secrets:
```bash
grep -r "ENC\[" kubernetes/apps --include="*.sops.yaml"
```

## Flux Kustomization Configuration

**Kustomization Template** (`kubernetes/apps/<namespace>/<app>/ks.yaml`):

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/kustomization-kustomize-v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app <app-name>
  namespace: &namespace <namespace>
spec:
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  decryption:
    provider: sops
    secretRef:
      name: sops-age
  dependsOn:
    - name: <dependency-app>
      namespace: <dependency-namespace>
  healthChecks:
    - apiVersion: helm.toolkit.fluxcd.io/v2
      kind: HelmRelease
      name: *app
      namespace: *namespace
  healthCheckExprs:
    - apiVersion: helm.toolkit.fluxcd.io/v2
      kind: HelmRelease
      failed: status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'False')
      current: status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'True')
  interval: 1h
  path: ./kubernetes/apps/<namespace>/<app>/app
  prune: true
  retryInterval: 2m
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: *namespace
  timeout: 5m
  wait: false
```

**Key Patterns:**
- Use YAML anchors for `name` and `namespace` to avoid typos
- Set `decryption.provider: sops` for all apps with secrets
- Define `healthChecks` for critical resources to track deployment status
- Set `interval: 1h` (standard polling interval)
- Set `retryInterval: 2m` (retry failed reconciliations)
- Set `wait: false` (don't block on app deployment, allow async syncing)

## Talos Configuration

**talconfig.yaml Pattern** (`talos/talconfig.yaml`):
- Uses `yaml-language-server` schema pointing to talhelper JSON schema
- All versions injected from `talenv.yaml` using template variables: `${talosVersion}`, `${kubernetesVersion}`
- Nodes defined with hostname, IP address, machine role, network interfaces, and customizations

**talenv.yaml:**
- Contains version overrides for Talos and Kubernetes
- Referenced by Renovate for automated version updates

**Talos Patches** (`talos/patches/`):
- Organized by target: `global/` (all nodes) and `controller/` (control-plane only)
- Named descriptively: `machine-network.yaml`, `machine-api.yaml`, etc.
- Patches applied via talhelper during config generation

## Shell Script Conventions

**Script Initialization** (`scripts/bootstrap-apps.sh`):
```bash
#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "${0}")/lib/common.sh"
```

**Error Handling:**
- Use `set -Eeuo pipefail` for strict error handling:
  - `-E`: Inherit ERR traps in functions
  - `-e`: Exit on error
  - `-u`: Fail on undefined variables
  - `-o pipefail`: Fail if any command in a pipe fails

**Logging Pattern** (from `scripts/lib/common.sh`):
```bash
export LOG_LEVEL="debug"  # Set global log level

log debug "Message here"
log info "Doing something" "resource=name" "status=active"
log warn "Warning message"
log error "Error message"  # Exits with code 1
```

**Log Levels:**
- `debug` (priority 1) — most verbose
- `info` (priority 2) — default
- `warn` (priority 3)
- `error` (priority 4) — exits process

**Environment Validation:**
```bash
check_env KUBECONFIG TALOSCONFIG           # Check required env vars
check_cli kubectl helm talosctl sops yq     # Check required CLI tools
```

**Directory Variables:**
```bash
export ROOT_DIR="$(git rev-parse --show-toplevel)"
export KUBECONFIG="${ROOT_DIR}/kubeconfig"
```

**Function Organization:**
- Define reusable functions with clear names (e.g., `wait_for_nodes`, `apply_namespaces`)
- Functions use local variables: `local -r app_dir="${ROOT_DIR}/kubernetes/apps"`
- Functions use descriptive comments and logging

**ShellCheck Configuration** (`.shellcheckrc`):
```
disable=SC1091     # Source file not found (OK for environment setup)
disable=SC2155     # Declare and assign separately (OK for convenience)
```

## Import and Resource Organization

**Kustomization Resource Lists:**
Resources are listed with relative paths, in logical order:

```yaml
resources:
  - ./clusterissuer.yaml
  - ./helmrelease.yaml
  - ./ocirepository.yaml
  - ./prometheusrule.yaml
  - ./secret.sops.yaml
```

**Component References:**
Components are referenced from shared component directories:

```yaml
components:
  - ../../components/alerts
  - ../../components/common
  - ../../../../components/authentik-proxy
```

## Commit Message Conventions

**Semantic Commit Format** (enforced by Renovate):
```
<type>(<scope>): <subject>
```

Commit types (by update type):
- `feat()` — minor/minor updates
- `fix()` — patch updates
- `chore()` — digest/dependency updates
- `ci()` — GitHub Actions updates
- `feat()!` — major updates (breaking change)

Example scopes (by resource type):
- `container` — container image updates
- `helm` — Helm chart version updates
- `github-action` — GitHub Actions
- `github-release` — release tools
- `mise` — tool version updates

Examples:
```
chore(container): image ghcr.io/mendhak/http-https-echo v41
feat(helm): chart cert-manager v1.16.0
ci(github-action): update actions/checkout to v6.0.3
fix(container): image ghcr.io/cilium/cilium v1.16.1
feat(mise)!: tool kubernetes-sigs/kustomize v6.0.0
```

---

*Convention analysis: 2026-04-24*
