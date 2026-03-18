# Copilot Instructions for home-ops

This repository is the GitOps source-of-truth for a Talos Kubernetes cluster (nicknamed **Zion**) running media, home automation, monitoring, and networking services. It uses FluxCD for reconciliation.

---

## Repo Layout

```
kubernetes/
  apps/           # All cluster applications, grouped by namespace
    default/      # Media & automation (Plex, Sonarr, Radarr, etc.)
    database/     # Dragonfly (Redis), CloudNativePG postgres cluster
    monitoring/   # VictoriaMetrics, Grafana, Loki, Gatus, etc.
    network/      # Envoy Gateway, Cloudflare Tunnel/DNS, UniFi DNS, Tailscale
    kube-system/  # Cilium, CoreDNS, Longhorn CSI, Reloader, Spegel, etc.
    cert-manager/ # cert-manager
    external-secrets/ # External Secrets Operator
    cnpg-system/  # CloudNativePG operator
  components/
    common/       # Shared namespace, repos, sops components
    alerts/       # Alertmanager + GitHub status alert components
  flux/
    cluster/      # Top-level FluxCD Kustomizations (cluster-meta, cluster-apps)
    meta/         # OCIRepositories and HelmRepositories used cluster-wide
talos/            # Talos machine configs via talhelper (talconfig.yaml, talenv.yaml, patches/)
bootstrap/        # Pre-Flux Helmfile charts
scripts/          # Helper scripts (e.g., bootstrap-apps.sh)
Taskfile.yaml     # Task automation
.mise.toml        # Tool version management
.sops.yaml        # SOPS encryption rules
.renovaterc.json5 # Renovate config for automated dependency updates
```

---

## Application Structure Convention

Every application lives at `kubernetes/apps/<namespace>/<app-name>/` and follows this pattern:

```
<app-name>/
  ks.yaml                   # FluxCD Kustomization (one per app)
  app/
    kustomization.yaml      # Lists all resources in this directory
    helmrelease.yaml        # HelmRelease (the main workload definition)
    ocirepository.yaml      # OCIRepository source for the Helm chart
    externalsecret.yaml     # ExternalSecret pulling from 1Password (if needed)
```

### Helm Charts
Most apps use **bjw-s-labs app-template** pulled via OCI:
```yaml
# ocirepository.yaml
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

Always add a `# yaml-language-server: $schema=...` comment at the top of YAML files — use the bjw-s app-template schema for HelmReleases that use that chart:
```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
```

### Kustomization (ks.yaml) Template
```yaml
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
    - name: longhorn        # if using Longhorn storage
      namespace: longhorn-system
  interval: 1h
  path: ./kubernetes/apps/<namespace>/<app-name>/app
  postBuild:
    substituteFrom:
      - name: cluster-secrets
        kind: Secret
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

After adding a new `ks.yaml`, add it to `kubernetes/apps/<namespace>/kustomization.yaml`.

---

## Variable Substitution

Flux performs `postBuild.substituteFrom` using a `cluster-secrets` Secret. Use `${SECRET_DOMAIN}` in resource definitions for the cluster's domain (e.g., hostnames, advertise URLs). This substitution is available in all app Kustomizations.

---

## Secrets

- **SOPS** (age-encrypted): Files matching `*.sops.yaml` under `kubernetes/` and `talos/` are encrypted. Only `data`/`stringData` fields are encrypted (see `.sops.yaml`). Never commit unencrypted secrets.
- **ExternalSecret**: Pulls secrets from 1Password via the `onepassword` ClusterSecretStore. Target secret names are referenced in HelmReleases via `envFrom.secretRef` or `env.secretKeyRef`.

ExternalSecret example:
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

---

## Container Security Context

All containers must use these security settings (drop ALL capabilities, no privilege escalation, read-only root filesystem):
```yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities: { drop: ["ALL"] }
```

Pod-level security context (non-root user):
```yaml
defaultPodOptions:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    fsGroupChangePolicy: OnRootMismatch
```

Always add a `tmp` emptyDir volume when `readOnlyRootFilesystem: true` is set:
```yaml
persistence:
  tmp:
    type: emptyDir
```

---

## Networking & Ingress

The cluster uses **Kubernetes Gateway API** via Envoy Gateway. There are two gateways in the `network` namespace:
- `envoy-external` — publicly accessible via Cloudflare Tunnel (`sectionName: https`)
- `envoy-internal` — home-network-only (`sectionName: https`)

Route example (inside HelmRelease values):
```yaml
route:
  app:
    hostnames:
      - "{{ .Release.Name }}.${SECRET_DOMAIN}"
    parentRefs:
      - name: envoy-internal   # or envoy-external
        namespace: network
        sectionName: https
```

**Do not use Ingress resources** — use HTTPRoute/Route via the Gateway API.

Network CIDRs:
- Nodes: `10.60.0.0/16`, gateway `10.60.0.1`
- Pod CIDR: `10.42.0.0/16` (IPv4), `fd00:42::/48` (IPv6)
- Service CIDR: `10.43.0.0/16` (IPv4), `fd00:43::/112` (IPv6)
- Cluster API VIP: `10.60.8.10:6443`

---

## Storage

- **Longhorn** is the default StorageClass (`storageClass: longhorn`).
- **NFS** share is available at `construct.${SECRET_DOMAIN}:/var/nfs/shared/data`, typically mounted at `/data`.
- Use `ReadWriteOnce` for most PVCs.

```yaml
persistence:
  config:
    accessMode: ReadWriteOnce
    size: 5Gi
    storageClass: longhorn
  data:
    type: nfs
    server: construct.${SECRET_DOMAIN}
    path: /var/nfs/shared/data
    globalMounts:
      - path: /data
```

---

## Databases

### PostgreSQL (CloudNativePG)
- **RW endpoint**: `postgres-cluster-rw.database.svc.cluster.local`
- **RO endpoint**: `postgres-cluster-r.database.svc.cluster.local`
- Credentials come from the secret `postgres-cluster-app` (keys: `user`, `password`).
- Apps like Sonarr/Radarr reference this via `secretKeyRef`.

### Dragonfly (Redis-compatible)
- Service: `dragonfly.database.svc.cluster.local:6379`
- Valid DB indexes: **0–15** (deployed with `--dbnum 16`)
- Uses standard Redis protocol.

---

## Config Reloading

Add this annotation to controller pods to have ReLoader automatically restart them when referenced Secrets or ConfigMaps change:
```yaml
annotations:
  reloader.stakater.com/auto: "true"
```

---

## Adding a New Application

1. Create `kubernetes/apps/<namespace>/<app-name>/ks.yaml` — the FluxCD Kustomization.
2. Create `kubernetes/apps/<namespace>/<app-name>/app/` with:
   - `kustomization.yaml` — lists all files in the directory
   - `ocirepository.yaml` — chart source
   - `helmrelease.yaml` — workload definition using bjw-s app-template
   - `externalsecret.yaml` — if secrets are needed from 1Password
3. Register the app by adding `- ./<app-name>/ks.yaml` to `kubernetes/apps/<namespace>/kustomization.yaml`.

---

## Tooling

Tools are managed by **mise** (`.mise.toml`). Key tools:
- `kubectl`, `flux`, `helm`, `kustomize`, `helmfile`
- `talosctl`, `talhelper` (Talos config generation)
- `sops`, `age` (secret encryption)
- `task` (Taskfile runner)
- `yq`, `jq`, `kubeconform`

Bootstrap:
```sh
mise trust && mise install
```

---

## Task Automation (Taskfile.yaml)

Common tasks:
```sh
task reconcile                            # Force Flux to pull from Git
task talos:generate-config                # Regenerate Talos machine configs
task talos:apply-node IP=10.60.85.10      # Apply config to a node
task talos:upgrade-node IP=10.60.85.10    # Upgrade Talos on a node
task talos:upgrade-k8s                    # Upgrade Kubernetes
task talos:reset                          # DESTRUCTIVE: reset nodes
```

Environment variables (set automatically via mise/Taskfile):
- `KUBECONFIG=./kubeconfig`
- `SOPS_AGE_KEY_FILE=./age.key`
- `TALOSCONFIG=./talos/clusterconfig/talosconfig`

---

## Flux Operations

```sh
flux check
flux get ks -A               # List all Kustomizations
flux get hr -A               # List all HelmReleases
flux get sources git -A      # List Git sources
flux reconcile kustomization flux-system --with-source
```

---

## CI / Pull Requests

On pull requests touching `kubernetes/**`, the `flux-local` workflow runs:
- **test**: validates all Kustomizations and HelmReleases resolve correctly
- **diff**: posts a rendered diff of HelmRelease/Kustomization changes as a PR comment

Always ensure your changes pass `flux-local test` before merging.

---

## Renovate

Renovate is configured to automatically update:
- Container image tags (including digest pinning)
- Helm chart versions via OCIRepository tags
- Talos/Kubernetes versions in `talenv.yaml`
- Mise tool versions in `.mise.toml`
- GitHub Actions

Commits follow **semantic commit** conventions (`feat:`, `fix:`, `chore:`, `ci:`).

---

## Cluster Nodes

| Hostname    | IP            | Role         | Notes                    |
|-------------|---------------|--------------|--------------------------|
| k8s-niobe   | 10.60.85.10   | control-plane | AMD, SecureBoot off      |
| k8s-trinity | 10.60.85.11   | control-plane | Intel iGPU, SecureBoot   |
| k8s-ghost   | 10.60.85.12   | control-plane | AMD, SecureBoot          |

VIP (Kube API): `10.60.8.10:6443`

---

## Key Namespaces

| Namespace         | Contents                                              |
|-------------------|-------------------------------------------------------|
| `default`         | Media & automation apps (Plex, Sonarr, Home Assistant, etc.) |
| `database`        | Dragonfly, CloudNativePG postgres cluster             |
| `monitoring`      | VictoriaMetrics stack, Grafana, Loki, Gatus           |
| `network`         | Envoy Gateway, Cloudflare Tunnel/DNS, UniFi DNS, Tailscale |
| `kube-system`     | Cilium, CoreDNS, Longhorn CSI, Reloader, Spegel, etc. |
| `cert-manager`    | cert-manager with wildcard certs                      |
| `external-secrets`| External Secrets Operator + 1Password store           |
| `cnpg-system`     | CloudNativePG operator                                |
| `longhorn-system` | Longhorn distributed storage                          |
| `flux-system`     | FluxCD controllers                                    |

---

## Troubleshooting

```sh
kubectl -n <ns> get pods -o wide
kubectl -n <ns> logs <pod> -f
kubectl -n <ns> describe <resource> <name>
kubectl -n <ns> get events --sort-by='.metadata.creationTimestamp'
flux get ks -A
flux get hr -A
```
