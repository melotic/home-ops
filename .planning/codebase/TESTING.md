# Testing Patterns

**Analysis Date:** 2026-04-24

## Testing Philosophy

This repository uses **configuration validation** rather than unit tests. The test strategy focuses on:
1. Kubernetes manifest validation (schema, syntax, compatibility)
2. Flux reconciliation validation (resources resolve correctly)
3. Rendered output comparison (what changes between commits)
4. Dependency validation (updates are compatible)

## Primary CI/CD Validation: flux-local

**Workflow File:** `.github/workflows/flux-local.yaml`

**Trigger:** Pull requests touching `kubernetes/**` files

**Workflow Stages:**

### Pre-Job: Changed Files Detection
- Detects if `kubernetes/**` files were modified
- Skips validation if no Kubernetes changes (efficiency)

```yaml
steps:
  - name: Get Changed Files
    id: changed-files
    uses: tj-actions/changed-files@47.0.6
    with:
      files: kubernetes/**
```

### Test Stage: flux-local Test

**Command:**
```bash
flux-local test \
  --enable-helm \
  --all-namespaces \
  --path /github/workspace/kubernetes/flux/cluster \
  --verbose \
  --sources flux-system
```

**What it validates:**
- All Kustomizations and HelmReleases in `kubernetes/flux/cluster` resolve correctly
- Helm charts can be templated without errors
- All referenced resources exist
- No circular dependencies
- Resource names are valid
- Schemas are satisfied

**Passes:**
- `✅` No unresolvable references
- `✅` All Helm charts template successfully
- `✅` All namespaces and names are unique

**Fails:**
- `❌` Unresolved `sourceRef` (missing OCIRepository/HelmRepository)
- `❌` Invalid Helm value types
- `❌` Missing required fields in HelmRelease
- `❌` Duplicate resource names in same namespace

### Diff Stage: flux-local Diff

**Command (dual checkout, compare):**
```bash
# Checkout PR branch
git checkout pull

# Checkout main branch for comparison
git checkout -f main

# Compare rendered outputs
flux-local diff helmrelease \
  --unified 6 \
  --path /workspace/pull/kubernetes/flux/cluster \
  --path-orig /workspace/main/kubernetes/flux/cluster \
  --strip-attrs "helm.sh/chart,checksum/config,app.kubernetes.io/version,chart" \
  --limit-bytes 10000 \
  --all-namespaces \
  --sources "flux-system" \
  --output-file diff.patch
```

**What it shows:**
- Human-readable diff of rendered HelmRelease values
- Shows exact changes to Kubernetes manifests (not just YAML diff)
- Strips non-relevant metadata (checksums, versions)
- Posts diff as PR comment for review

**Diff posted as:**
```markdown
### Diff

\`\`\`diff
--- helmrelease/cert-manager/cert-manager
+++ helmrelease/cert-manager/cert-manager
@@ ... @@
  spec:
    image:
      repository: ghcr.io/cert-manager/cert-manager
-     tag: "1.14.0"
+     tag: "1.15.0"
    replicaCount: 1
\`\`\`
```

### Status Aggregation

All workflow jobs must pass (or skip):
- `test` — must pass if Kubernetes files changed
- `diff` — generates informational output
- `flux-local-status` — final gate that requires all previous jobs to succeed

**Run Command:**
```bash
./github/workflows/flux-local.yaml
  on pull_request:
    branches: [main]
```

## Schema Validation

**Mechanism:** YAML Language Server (IDE + CI)

**Schema Declarations:**
Every YAML file includes a schema comment for validation:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/kustomization-kustomize-v1.json
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
```

**Validated On:**
- **Local development:** IDE validation (VS Code, Neovim, etc.)
- **Pull request:** Pre-commit hooks can validate locally before pushing
- **Manual check:** `kubecm validate` or similar tools

**Schema Sources:**
- FluxCD official schemas: `https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/`
- Kubernetes schemas: `https://kubernetes-schemas.pages.dev/`
- JSON Schema Store: `https://json.schemastore.org/`

## Kubernetes Manifest Validation

**Tool:** `kubeconform` (included in `.mise.toml`)

**Manual Validation:**
```bash
# Install via mise
mise install

# Validate all Kubernetes manifests
kubeconform -summary -output json kubernetes/
```

**What kubeconform validates:**
- ✅ Kubernetes API versions are valid
- ✅ Kind names are recognized
- ✅ Required fields are present
- ✅ Field types match schema (string, number, array, etc.)
- ✅ Enum values are correct

**Error Example:**
```
kubernetes/apps/cert-manager/cert-manager/app/helmrelease.yaml - HelmRelease cert-manager: missing required field "spec.chartRef"
```

## Shell Script Validation

**Tool:** `shellcheck` (configured in `.shellcheckrc`)

**Configuration** (`.shellcheckrc`):
```
disable=SC1091     # OK: source file not found (environmental setup)
disable=SC2155     # OK: declare and assign in one line (convenience)
```

**Disabled Checks:**
- `SC1091` — allows sourcing from environment without strict file checks
- `SC2155` — allows `export VAR="$(command)"` pattern

**Manual Check:**
```bash
# Install
mise install

# Check scripts
shellcheck scripts/*.sh scripts/lib/*.sh
```

**Common Issues Caught:**
- ❌ Undefined variables
- ❌ Missing quotes around `$variables`
- ❌ Unused variables
- ❌ Syntax errors
- ❌ Non-portable shell constructs

## Dependency Validation: Renovate

**Configuration File:** `.renovaterc.json5`

**Automated Checks:**
1. **Container Image Digests** — Pins image digests to detect supply chain attacks
2. **Helm Chart Versions** — Detects new chart releases via OCIRepository tags
3. **GitHub Actions** — Updates to actions with digest pinning
4. **Talos/Kubernetes Versions** — Updates from `talenv.yaml`
5. **Mise Tool Versions** — Updates from `.mise.toml`

**Schedule:** Weekend runs to prevent mid-week disruptions

**Commit Validation (Semantic Commits):**
```json
{
  "matchUpdateTypes": ["major"],
  "semanticCommitType": "feat",
  "commitMessagePrefix": "{{semanticCommitType}}({{semanticCommitScope}})!:"
}
```

Renovate automatically creates PRs with commits like:
- `chore(container): image ghcr.io/org/app v1.2.3`
- `feat(helm): chart cert-manager v1.15.0`
- `ci(github-action): action actions/checkout v6`

## Local Pre-Commit Validation

**Recommended Workflow:**
```bash
# Before committing locally:

# 1. Validate schemas
flux-local test --enable-helm --all-namespaces --path kubernetes/flux/cluster -v

# 2. Check shell scripts
shellcheck scripts/*.sh scripts/lib/*.sh

# 3. Verify no unencrypted secrets
grep -r "ENC\[" kubernetes/**/*.sops.yaml

# 4. Check YAML syntax
yamllint kubernetes/

# 5. Preview rendered manifests (optional)
flux-local diff helmrelease \
  --path kubernetes/flux/cluster \
  --sources flux-system
```

## Configuration Validation Checks

### Kustomization Validation

**Checks Performed by flux-local test:**

1. **Kustomization Resource Presence**
   ```yaml
   spec:
     sourceRef:
       kind: GitRepository
       name: flux-system
       namespace: flux-system
   ```
   ✅ Verifies GitRepository exists with that name in flux-system namespace

2. **Chart References**
   ```yaml
   spec:
     chartRef:
       kind: OCIRepository
       name: cert-manager
   ```
   ✅ Verifies OCIRepository with that name exists

3. **Namespace Targeting**
   ```yaml
   spec:
     targetNamespace: cert-manager
   ```
   ✅ Validates namespace will be created or exists

4. **Health Checks**
   ```yaml
   spec:
     healthChecks:
       - apiVersion: helm.toolkit.fluxcd.io/v2
         kind: HelmRelease
         name: cert-manager
         namespace: cert-manager
   ```
   ✅ Verifies health check targets exist and are healthy

### HelmRelease Validation

1. **Chart Reference Resolution**
   - Resolves OCIRepository to actual Helm chart
   - Fetches and templates the chart
   - Validates Helm values against chart schema

2. **Dependency Ordering**
   ```yaml
   spec:
     dependsOn:
       - name: <other-app>
         namespace: <other-namespace>
   ```
   ✅ Ensures dependent apps are deployed first

3. **Install/Upgrade Remediation**
   ```yaml
   spec:
     install:
       remediation:
         retries: -1
     upgrade:
       cleanupOnFail: true
       remediation:
         retries: 3
   ```
   ✅ Validates retry counts and cleanup policies are sensible

### Secret Validation

1. **SOPS Encryption Status**
   - Checks that `*.sops.yaml` files are actually encrypted
   - Pre-commit hook should prevent committing unencrypted files

2. **ExternalSecret References**
   ```yaml
   spec:
     secretStoreRef:
       kind: ClusterSecretStore
       name: onepassword
   ```
   ✅ Verifies SecretStore exists

## Testing Results Interpretation

### ✅ Test Passes

All Kustomizations and HelmReleases:
- Resolve without errors
- Reference valid sources
- Have valid schemas
- Can be templated into manifests

**In Practice:**
```
✅ kustomization/cert-manager/cert-manager reconciliation OK
✅ helmrelease/cert-manager/cert-manager reconciliation OK
✅ kustomization/default/echo reconciliation OK
✅ helmrelease/default/echo reconciliation OK
```

### ❌ Test Failures

Common failure modes and fixes:

**1. Missing OCIRepository**
```
Error: OCIRepository cert-manager not found in flux-system namespace
Fix: Ensure cert-manager ocirepository.yaml exists in kubernetes/apps/cert-manager/cert-manager/app/
```

**2. Invalid Helm Values**
```
Error: field "spec.interval" must be a string matching regex "^[0-9]+(ns|us|ms|s|m|h)$"
Fix: Ensure interval: 1h (not interval: 1h5m - must be single unit)
```

**3. Circular Dependencies**
```
Error: circular dependency detected: app-a depends on app-b depends on app-a
Fix: Review dependsOn fields for cycles
```

**4. Unresolved Image References**
```
Error: image ghcr.io/my-org/broken:tag could not be pulled
Fix: Verify image exists and tag is correct
```

**5. Secret Key Mismatch**
```
Error: key "missing_key" not found in secret "my-secret"
Fix: Verify ExternalSecret dataFrom matches 1Password vault item keys
```

## Manual Testing / Local Verification

### Bootstrap Validation

```bash
# 1. Verify Talos configuration
task talos:generate-config
# Generates valid Talos machine configs without errors

# 2. Verify SOPS secrets
sops exec-file kubernetes/components/common/sops/sops-age.sops.yaml \
  "kubectl --namespace flux-system apply --server-side --filename {}"
# Decrypts and applies without error

# 3. Verify Kustomize build
kustomize build kubernetes/apps/cert-manager/
# Generates valid YAML without errors

# 4. Apply to dry-run
kubectl apply --server-side --dry-run=server -f <(kustomize build kubernetes/apps)
# Succeeds without conflicts or validation errors
```

### Flux Health Checks

```bash
# Reconcile Flux cluster-meta (repositories, namespaces)
flux reconcile kustomization cluster-meta --with-source

# Reconcile cluster apps
flux reconcile kustomization cluster-apps --with-source

# Check all Kustomizations
flux get ks -A

# Check all HelmReleases
flux get hr -A

# View detailed status
kubectl -n cert-manager get helmrelease cert-manager -o wide
```

## CI Pipeline Execution

**On Pull Request (when `kubernetes/**` changes):**

1. ✅ **Pre-job** — Detects changed files
2. ✅ **Test job** — flux-local validates all resources resolve
3. ✅ **Diff job** — Generates PR comment showing rendered changes
4. ✅ **Status job** — Passes if all jobs succeeded/skipped

**On Merge to Main:**
- Flux in-cluster controller detects Git changes
- Automatically reconciles affected Kustomizations
- Monitors health checks
- Alerts on failures

## Test Coverage Strategy

**What IS tested:**
- ✅ Kubernetes schema compliance
- ✅ Flux Kustomization and HelmRelease validation
- ✅ Chart templating (Helm values render correctly)
- ✅ Resource dependency order
- ✅ Secret references (exist and have keys)
- ✅ Image digest pinning (supply chain integrity)

**What IS NOT tested:**
- ❌ Application runtime behavior (functional testing)
- ❌ Pod startup success (integration test — runs after merge)
- ❌ Network connectivity between pods
- ❌ Persistent data handling

**Rationale:**
- Runtime behavior validated by Flux health checks in cluster
- Pull requests focus on configuration correctness
- Failed deployments trigger cluster alerts (Prometheus/Alertmanager)

---

*Testing analysis: 2026-04-24*
