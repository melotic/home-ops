# Codebase Concerns

**Analysis Date:** 2026-04-24

## Resource Management & Reliability

**Missing Resource Constraints:**
- Issue: Only 37 of 346 Kubernetes manifests define `requests` or `limits`. Most workloads in `kubernetes/apps/` lack CPU/memory constraints.
- Files: `kubernetes/apps/default/`, `kubernetes/apps/monitoring/`, `kubernetes/apps/database/` — especially media stack apps like `sonarr`, `radarr`, `lidarr`, `sabnzbd`, `plex`
- Impact: Cluster node pressure will cause evictions with no protection; noisy neighbors can starve critical services; Kubernetes scheduler cannot make informed decisions
- Fix approach: Add resource requests/limits to all HelmRelease and Kustomization resources. Start with monitoring and critical services, then media workloads. Use infrastructure-level defaults via LimitRange if needed.

**Single Replicas for Critical Services:**
- Issue: `cert-manager` (1 replica in `kubernetes/apps/cert-manager/cert-manager/app/helmrelease.yaml`), many observability tools, and application services run with `replicaCount: 1`
- Files: `kubernetes/apps/cert-manager/cert-manager/app/helmrelease.yaml:23`, `kubernetes/apps/monitoring/victoria-metrics-k8s-stack/app/helmrelease.yaml`, `kubernetes/apps/default/authentik/app/helmrelease.yaml`
- Impact: Pod evictions, node maintenance, or crashes cause service downtime; no high availability
- Fix approach: Configure at least 2 replicas for cert-manager, Grafana, Victoria Metrics. Use pod disruption budgets (PDB) to allow safe evictions. Review replica counts during bootstrap.

**No Pod Disruption Budgets (PDB):**
- Issue: No PDB resources found in `kubernetes/apps/`. Cluster node drains or maintenance can immediately evict all replicas of critical workloads.
- Files: No PDB found across `kubernetes/apps/`
- Impact: Planned node maintenance (e.g., Talos updates via `task talos:upgrade-node`) will disrupt services with multiple replicas
- Fix approach: Add PDB for all stateful services and critical workloads. Ensure `minAvailable: 1` for services with 2+ replicas.

## Security & Hardening

**Incomplete Security Contexts:**
- Issue: Only 64 instances of `securityContext` across 346 files. Most applications don't explicitly define security policies like `runAsNonRoot`, `readOnlyRootFilesystem`, or capability drops.
- Files: Media apps in `kubernetes/apps/default/` (`sonarr`, `radarr`, `lidarr`, `plex`, `home-assistant`, `paperless-ngx`) lack security contexts entirely
- Impact: Containers may run as root; processes can write arbitrary system files; default capabilities allow privilege escalation
- Fix approach: Add `securityContext` to all containers with `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `capabilities: {drop: ["ALL"]}` as base, then relax only when necessary. See `kubernetes/apps/default/echo/app/helmrelease.yaml:82` for pattern.

**No Network Policies:**
- Issue: Only 2 `networkPolicy` resources across entire cluster
- Files: `kubernetes/apps/` lacks egress/ingress policies
- Impact: All pods can communicate with all other pods by default; lateral movement in case of breach is unrestricted
- Fix approach: Implement deny-all network policies per namespace, then selectively allow required traffic. Start with namespace-scoped policies for data access (e.g., allow `default` apps to reach Postgres in `database` namespace).

**No Image Pull Policies:**
- Issue: `imagePullPolicy` not explicitly set in any helmrelease. Kubernetes defaults to `IfNotPresent`, but this is implicit and fragile.
- Files: All helmrelease files in `kubernetes/apps/` (e.g., `kubernetes/apps/default/echo/app/helmrelease.yaml`)
- Impact: If an image is cached locally, a newer tag won't be pulled; stale images may persist after registry updates
- Fix approach: Add `imagePullPolicy: Always` to all containers that use mutable tags (not digests). Use immutable digests (e.g., `ghcr.io/atuinsh/atuin:18.15.2@sha256:...`) where possible.

**No Service Accounts with RBAC:**
- Issue: No explicit `serviceAccountName` or RBAC bindings found in app deployments
- Files: `kubernetes/apps/` across all namespaces
- Impact: Pods inherit default service account permissions; if compromised, attacker has default cluster access
- Fix approach: Create namespace-scoped service accounts for each application tier. Bind minimal RBAC roles required for operation.

## Cluster Architecture & Availability

**Inconsistent Node Configuration:**
- Issue: Three control-plane nodes (niobe, trinity, ghost) have inconsistent secureboot settings. `k8s-niobe` has `secureboot: false` while `k8s-trinity` and `k8s-ghost` have `secureboot: true`.
- Files: `talos/talconfig.yaml:26, 55, 83`
- Impact: Security posture is inconsistent; firmware vulnerabilities on one node cannot be fully mitigated if secureboot is disabled
- Fix approach: Enable secureboot on all nodes, or document why `k8s-niobe` requires it disabled. Test firmware updates on a staging node before rolling out.

**Shared VIP with Single Endpoint:**
- Issue: All three control-plane nodes share VIP `10.60.8.10` (line 39, 68, 96 in `talos/talconfig.yaml`). Single API endpoint for all nodes means:
  - DNS points to one address
  - Network switch/firewall rules center on one IP
  - No redundancy at IP layer if VIP service fails
- Files: `talos/talconfig.yaml:8, 39, 68, 96`
- Impact: Loss of VIP service (HA failover) is single point of failure even with 3 nodes
- Fix approach: Use separate load balancer (hardware or software) with health checks. Document VIP failover behavior and test it regularly.

**All Nodes on Same Disk Device:**
- Issue: All three nodes use same install disk path `/dev/nvme0n1`
- Files: `talos/talconfig.yaml:24, 53, 80`
- Impact: If cluster is deployed in environment where multiple nodes share storage (unlikely but possible in lab settings), disk naming may conflict
- Fix approach: Verify disk mapping per node before deployment. Update nodes.yaml with correct device per hardware.

**Longhorn Disk Provisioning with Minimum Size Gap:**
- Issue: Longhorn `minSize: 128GiB` and `maxSize: 1TiB` without explicit handling for edge cases. If a node's available disk is between min/max, provision could fail silently.
- Files: `talos/talconfig.yaml:123-126`
- Impact: Replicated volumes might not schedule if min/max are too strict
- Fix approach: Document actual available disk on each node. Set minSize to 80% of usable storage, maxSize to 90%.

## Operational Fragility

**Bootstrap Wait Loops with Indefinite Retries:**
- Issue: `scripts/bootstrap-apps.sh` and bootstrap Taskfile use `until` loops with 10-second sleep without timeout limit or retry count
- Files: `.taskfiles/bootstrap/Taskfile.yaml:14, 15` (`until talhelper gencommand bootstrap | bash; do sleep 10; done`)
- Impact: If bootstrap command continues to fail, the loop runs indefinitely. No alerting or human intervention mechanism.
- Fix approach: Add timeout constraint (e.g., `timeout 30m`) to until loops. Add max retry count with explicit failure exit.

**Manual Task Preconditions Without Inline Guidance:**
- Issue: Tasks like `talos:apply-node` require `IP=` parameter but provide no guidance on discovering valid IPs. Precondition `talosctl --nodes {{.IP}} get machineconfig` will fail with cryptic error if IP is wrong.
- Files: `.taskfiles/talos/Taskfile.yaml:17-29`
- Impact: Operators may pass invalid IPs; error messages are not user-friendly
- Fix approach: Add validation task that lists available node IPs. Document IP discovery step in README.

**Generated Cluster Config Not in Git:**
- Issue: `talos/clusterconfig/` contains generated configs (`kubernetes-k8s-*.yaml`, `talosconfig`) which are in `.gitignore`. Three times 189 lines (567 total) of generated state not tracked.
- Files: `talos/clusterconfig/.gitignore` (ignores all except sample files), `talos/talconfig.yaml` is source of truth
- Impact: If talhelper binary version or talconfig.yaml changes, regenerating configs on different machine may produce different results (version drift, schema changes). No audit trail of config changes.
- Fix approach: Commit generated configs to git with clear marker (e.g., in `git-attributes`). Document regeneration process.

## Secrets & Sensitive Data

**Limited Secret Encryption Coverage:**
- Issue: Only 3 SOPS-encrypted files across entire cluster: `cert-manager` secret, `cloudflare-dns` secret, `cloudflare-tunnel` secret
- Files: `kubernetes/apps/cert-manager/cert-manager/app/secret.sops.yaml`, `kubernetes/apps/network/cloudflare-dns/app/secret.sops.yaml`, `kubernetes/apps/network/cloudflare-tunnel/app/secret.sops.yaml`
- Impact: Most app secrets sourced from 1Password via External Secrets. Single point of failure if 1Password integration breaks; secret rotation is manual and opaque.
- Fix approach: Audit all app secrets. Move frequently-rotated secrets to SOPS. Document which secrets are in 1Password vs. SOPS.

**Database Credentials via File Injection:**
- Issue: Postgres credentials passed via `password: file:///postgres-creds/password` in Authentik config (`kubernetes/apps/default/authentik/app/helmrelease.yaml`)
- Files: `kubernetes/apps/default/authentik/app/helmrelease.yaml:16-17`
- Impact: Credentials must be injected as files; workflow depends on external secret provisioning. If file is not readable, app fails silently until logs are checked.
- Fix approach: Use external-secrets-operator to provide credentials consistently. Document secret sourcing in app README.

**Age Key in Repository Root:**
- Issue: `age.key` file present in root directory (used for SOPS encryption)
- Files: `./age.key` (noted in Taskfile env vars)
- Impact: Private key in repo allows anyone with repo access to decrypt secrets. Should be excluded from git.
- Fix approach: Add `age.key` to `.gitignore` immediately. Regenerate age key. Rotate all encrypted secrets.

## Storage & Persistence

**Limited Persistent Volume Usage:**
- Issue: Only 8 files with persistent volume references; many stateful apps (Plex, media servers, Authentik) may not have explicit volume provisioning visible
- Files: `kubernetes/apps/default/plex/app/helmrelease.yaml`, `kubernetes/apps/default/authentik/app/helmrelease.yaml` — most PVC logic in helm chart, not visible in kustomization
- Impact: Storage provisioning is opaque. Volume reclamation policies and backup procedures unknown. Loss of node may cause data loss if volumes are not replicated.
- Fix approach: Document storage architecture per app. Use Longhorn replication=2 for critical data. Add Kopia backup integration for verification.

**Longhorn Storage Class Mixing:**
- Issue: Multiple storage classes used (`nfs-construct`, `longhorn`, others) with no clear documentation of when to use which
- Files: `kubernetes/apps/default/harbor/app/helmrelease.yaml:83` uses `nfs-construct`, while others use `longhorn`
- Impact: Performance characteristics and availability guarantees differ by class; operator confusion on provisioning
- Fix approach: Create storage class decision matrix in README. Use longhorn for critical, NFS for non-critical.

## Observability & Monitoring

**Observability Apps in Single Namespace:**
- Issue: All monitoring/observability apps (`victoria-metrics`, `grafana`, `loki`, `gatus`) in single `monitoring` namespace with single namespace-scoped alerts
- Files: `kubernetes/apps/monitoring/` directory
- Impact: Failure of central observability breaks all monitoring; no redundancy
- Fix approach: Deploy second monitoring stack in separate namespace for high availability. Federation of Prometheus/Grafana recommended.

**No Alertmanager Webhook Targets Visible:**
- Issue: AlertManager configured in `kubernetes/components/alerts/alertmanager/` but webhook targets not visible in main YAML files
- Files: `kubernetes/components/alerts/alertmanager/provider.yaml` (if exists, not fully explored)
- Impact: Alert delivery is opaque; unclear if alerts actually reach human operators
- Fix approach: Document alertmanager routing rules and webhook endpoints clearly.

## Dependency & Version Management

**Tool Version Pinning in Mise:**
- Issue: `.mise.toml` pins specific versions (Flux 2.8.6, Talos 1.12.6, Helm 4.1.4, etc.). Renovate updates these, but compatibility across tool versions not explicitly tested.
- Files: `.mise.toml:8-26`
- Impact: If Renovate updates FluxCD but Talos CLI isn't compatible, bootstrap fails mysteriously
- Fix approach: Create tool compatibility matrix in README. Test major version updates in CI before merging.

**Renovate Configuration Complexity:**
- Issue: `.renovaterc.json5` has extensive custom regex matchers for datasources and managers. Regex patterns for version extraction are fragile and hard to maintain.
- Files: `.renovaterc.json5:133-168`
- Impact: Custom patterns may fail silently if format changes; version updates missed
- Fix approach: Review and test custom regex monthly. Add logging to Renovate runs to catch missed updates.

## Testing & Validation

**No Manifests Validation in CI:**
- Issue: No evidence of `kubeconform` or `kube-score` validation on Kubernetes manifests before merge
- Files: `.mise.toml:26` lists kubeconform but no CI workflow using it
- Impact: Invalid manifests can be committed; Flux reconciliation fails at apply time
- Fix approach: Add pre-commit hook or GitHub workflow to validate all `*.yaml` against Kubernetes schema.

**Bootstrap Script Lacks Error Handling:**
- Issue: `scripts/bootstrap-apps.sh` uses `set -Eeuo pipefail` but doesn't validate intermediate steps (namespace creation may fail, Kustomization may not exist)
- Files: `scripts/bootstrap-apps.sh:28-50`
- Impact: Script may proceed past failures; cluster state undefined
- Fix approach: Add explicit error checking after each major step. Log state before and after.

## Scale & Performance Concerns

**Large Default Namespace Workload Density:**
- Issue: 30+ applications packed in `kubernetes/apps/default/` namespace (plex, sonarr, radarr, lidarr, tautulli, paperless-ngx, home-assistant, etc.)
- Files: `kubernetes/apps/default/kustomization.yaml:10-36` lists 26 apps
- Impact: Single namespace has high blast radius; resource contention between media apps; harder to troubleshoot
- Fix approach: Separate media apps into `media` namespace, home automation into `automation` namespace. Reduces cardinality per namespace.

**Authnet Blueprints Inline in ConfigMaps:**
- Issue: Authentik blueprints are 15+ separate YAML files in `kubernetes/apps/default/authentik/app/blueprints/`, each 100-200 lines. Inline in kustomization.
- Files: `kubernetes/apps/default/authentik/app/blueprints/` (brand.yaml 155 lines, flow-login.yaml 195 lines, etc.)
- Impact: Blueprints are hard to version-control separately; any blueprint change requires Authentik pod restart
- Fix approach: Export blueprints to external ConfigMap sources or use Authentik's remote blueprint URL support.

## Documentation & Clarity

**Sample Files Require Manual Intervention:**
- Issue: `cluster.sample.yaml` and `nodes.sample.yaml` are templates; no automated way to validate filled versions before bootstrap
- Files: `./cluster.sample.yaml`, `./nodes.sample.yaml`
- Impact: Operators may misconfigure IPs, DNS, or domains without immediate feedback
- Fix approach: Create `task validate:cluster` that validates filled YAML against schema before bootstrap. Document all fields.

**Hardware MAC Address Hardcoding:**
- Issue: MAC addresses hardcoded in `talconfig.yaml` (lines 30, 59, 87)
- Files: `talos/talconfig.yaml:30, 59, 87`
- Impact: If NICs are replaced, config must be updated manually. No discovery mechanism for new hardware.
- Fix approach: Document NIC discovery process (`talosctl get links`). Consider hardware abstraction layer or environment variables.

**Patch Organization Complexity:**
- Issue: Talos patches split into `global/` (7 files) and `controller/` (2 files) with included `controlPlane` patches via `userVolumes`. Interdependencies not explicit.
- Files: `talos/patches/`, `talos/talconfig.yaml:108-138`
- Impact: Hard to understand which patches apply to which nodes; easy to miss patches during updates
- Fix approach: Add patch documentation matrix (which nodes, what purpose, any dependencies).

## Fragile Patterns

**All Apps Depend on Single Cloudflare Tunnel:**
- Issue: Many apps reference `cloudflare-tunnel` in `dependsOn` field, or via ingress `parentRefs` (e.g., `kubernetes/apps/default/echo/app/helmrelease.yaml:45-48`)
- Files: `kubernetes/apps/default/echo/app/helmrelease.yaml`, `kubernetes/apps/network/cloudflare-tunnel/app/helmrelease.yaml`
- Impact: If Cloudflare Tunnel pod is evicted or crashes, all external ingress fails immediately
- Fix approach: Deploy 2+ replicas of cloudflare-tunnel with pod disruption budget. Use DNS failover as fallback.

**Namespace Anchors & Aliases Scattered:**
- Issue: Kustomization files use YAML anchors (`&namespace`) and aliases (`*namespace`) to reference namespaces. If namespace definition changes, aliases break silently.
- Files: `kubernetes/apps/cert-manager/cert-manager/ks.yaml:2`, `kubernetes/apps/default/echo/ks.yaml:2`
- Impact: Hard to trace namespace changes; refactoring is error-prone
- Fix approach: Use Kustomize variables or structured namespaceRef instead of YAML anchors.

---

*Concerns audit: 2026-04-24*
