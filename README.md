# home-ops

This repo is the GitOps source-of-truth for a Talos Kubernetes cluster running media, home automation, monitoring, and network services, nicknamed Zion.

## 🧩 Stack & Choices

- Talos Linux for immutable nodes and declarative machine config.
- FluxCD for reconciliation of `Kustomization` and `HelmRelease`.
- CNI: Cilium. Ingress/Gateway: Kubernetes Gateway API.
- Storage: Longhorn (+ CSI drivers where needed).
- Databases: CloudNativePG for Postgres.
- Secrets: SOPS (age) and External Secrets with 1Password.
- Certificates: cert-manager with wildcard certs.
- Distribution helpers: Spegel; config reloads via ReLoader.
- Access: Cloudflare Tunnel and DNS; UniFi DNS integration for home network.

## 🧰 Apps

Media & automation (namespace `default`):
- Plex, Sonarr, Radarr, Lidarr, Tautulli
- Prowlarr, Sabnzbd, Recyclarr, Seerr
- Home Assistant, Atuin, Echo demo
- Postgres clients/workloads under `psql-apps`

Observability (namespace `monitoring`):
- kube-prometheus-stack, Grafana, Loki, Gatus, Unpoller

Networking (namespace `network`):
- Cloudflare DNS, Cloudflare Tunnel, UniFi DNS

Platform:
- External Secrets (incl. 1Password), cert-manager, Flux system, CNPG system, CoreDNS, Cilium, Longhorn

## 🚀 Bootstrap

Prereqs (installed via Mise): `kubectl`, `talosctl`, `helm`, `flux`, `sops`, `age`, `cloudflared`, `jq`, `yq`.

```sh
mise trust
pip install pipx
mise install
```

Initialize and configure:

```sh
task init
# edit cluster.yaml and nodes.yaml based on my environment
task configure
git add -A && git commit -m "chore: initial setup" && git push
```

Bootstrap Talos and core apps:

```sh
task bootstrap:talos
task bootstrap:apps
kubectl get pods -A --watch
```

Cloudflare:

```sh
cloudflared tunnel login
cloudflared tunnel create --credentials-file cloudflare-tunnel.json kubernetes
```

Public routes use the `external` gateway; internal-only use the `internal` gateway. Home DNS is handled via UniFi DNS and cluster CoreDNS; split-DNS is configured so `${cloudflare_domain}` resolves internally to the cluster gateway.

## 📂 Repo Layout

- [kubernetes/apps](kubernetes/apps): Apps per area (default, kube-system, monitoring, network, etc.).
- [kubernetes/components](kubernetes/components): shared namespaces, repos, sops.
- [kubernetes/flux](kubernetes/flux): cluster bootstrap and metadata.
- [bootstrap/helmfile.d](bootstrap/helmfile.d): pre-Flux bootstrapping charts.
- [talos](talos): talconfig, talenv, patches, clusterconfig.
- [scripts](scripts): helper scripts like `bootstrap-apps.sh`.
- [Taskfile.yaml](Taskfile.yaml): task automation.

## 🛠 Operations

- Flux reconcile and status:

```sh
task reconcile
flux check
flux get ks -A
flux get hr -A
```

- Talos config/apply:

```sh
task talos:generate-config
task talos:apply-node IP=10.10.10.10 MODE=auto
```

- Upgrades:

```sh
task talos:upgrade-node IP=10.10.10.10
task talos:upgrade-k8s
```

- Reset (destructive):

```sh
task talos:reset
```

## 🔐 Secrets

- SOPS-encrypted files live in [kubernetes](kubernetes) and [talos](talos).
- Verify `./kubernetes/**/*.sops.*` are encrypted before pushing.
- External Secrets sources secrets from 1Password where appropriate.

## 🐛 Troubleshooting

```sh
flux get sources git -A
flux get ks -A
flux get hr -A
kubectl -n <ns> get pods -o wide
kubectl -n <ns> logs <pod> -f
kubectl -n <ns> describe <resource> <name>
kubectl -n <ns> get events --sort-by='.metadata.creationTimestamp'
```

## 🧹 Tidy

When the cluster configuration is stable, remove unused templating artifacts:

```sh
task template:tidy
git add -A && git commit -m "chore: tidy" && git push
```

## 📄 License

See [LICENSE](LICENSE).
