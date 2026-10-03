# AGENTS.md

GitOps source-of-truth for the Talos Kubernetes cluster "Zion" (FluxCD reconciliation).
The unit of deployment is `kubernetes/apps/<namespace>/<app>/` with a Flux `Kustomization`
(`ks.yaml`) plus `app/` (kustomization.yaml, ocirepository.yaml, helmrelease.yaml,
externalsecret.yaml). Most charts use bjw-s-labs app-template via OCI.

## Setup / environment

- `mise trust && mise install` — all tools (kubectl, talosctl, flux, helm, sops, just, flate, yamlfmt…)
  are pinned in `.mise.toml`. Run `just` from a mise-activated shell.
- `.mise.toml` `[env]` exports the paths recipes rely on:
  `KUBECONFIG=./kubeconfig`, `SOPS_AGE_KEY_FILE=./age.key`, `TALOSCONFIG=./talos/talosconfig`
  (all gitignored, all must exist for talos/kube/sops recipes to work).

## Verify changes (in order)

1. `mise exec -- flate test all --path kubernetes/flux/cluster` — required before merging K8s changes (runs in CI on PRs touching `kubernetes/**`).
2. `yamlfmt -lint` — CI lint for `**/*.yaml|yml` (config `.yamlfmt.yaml`). Rules that differ from defaults: files keep a leading `---`, blank-line grouping is preserved, `**/*.sops.yaml` and `talos/**` are excluded.
3. Format with `yamlfmt` (write mode, no flag) before committing YAML.
4. PR titles must be Conventional Commits with a component scope (squash-merge becomes the commit message).

No unit-test suite exists; CI is flate + yamlfmt + tflint + kubeconform (`.github/workflows/`).

## Adding an app

1. `kubernetes/apps/<namespace>/<app>/ks.yaml` — Flux Kustomization. Copy an existing app's `ks.yaml` (always set `decryption: sops` secretRef `sops-age`, `sourceRef` GitRepository `flux-system`, `targetNamespace`, `postBuild.substituteFrom` secret `cluster-secrets`).
2. `app/` directory with kustomization.yaml, ocirepository.yaml, helmrelease.yaml (+ externalsecret.yaml if needed).
3. Register `app-name/ks.yaml` in `kubernetes/apps/<namespace>/kustomization.yaml`.
4. Header comment on every YAML file: `# yaml-language-server: $schema=...` (bjw-s schema for app-template HelmReleases; fluxcd-community flux2-schemas for Kustomizations).

## Conventions that differ from defaults

- **No Ingress resources.** Use Gateway API (HTTPRoute etc.) with parent gateway
  `envoy-external` (public, via Cloudflare Tunnel) or `envoy-internal` (LAN-only), in namespace `network`, `sectionName: https`.
- **Domain is hardcoded** `melotic.dev`; `cluster-secrets` postBuild substitution only provides `${IPV6_PREFIX}`.
- **Security context mandatory**: `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `capabilities: {drop: ["ALL"]}`, pod `runAsNonRoot`/uid 1000; add `tmp` emptyDir when rootfs is read-only.
- **Storage**: default `ceph-block` (RBD); CephFS via `ceph-filesystem`; CNPG/Postgres uses `openebs-hostpath` (do not move to Ceph). NFS at `construct.melotic.dev:/var/nfs/shared/data` → `/data`.
- **Postgres**: CNPG cluster `postgres-cluster` in `database` ns; app creds via secret `postgres-user-<app>`. Dragonfly (Redis) at `dragonfly.database:6379`, DBs 0–15 only.
- **Config reloads**: annotate controllers with `reloader.stakater.com/auto: "true"` (ReLoader).
- **Secrets**: `*.sops.yaml` under `kubernetes/` and `talos/` are age-encrypted (`encrypted_regex: "^(data|stringData)$"` — everything else stays plaintext). Never commit decrypted secrets; verify with `sops -d` before pushing. Runtime secrets come from ExternalSecret → 1Password (`ClusterSecretStore: onepassword`).
- **SOPS/age key**: repo root `age.key`, decrypt-only; never commit it.

## Network layout

- Nodes 10.60.0.0/16 (API VIP `10.60.8.10:6443`), pods 10.42.0.0/16 + fd00:42::/48, services 10.43.0.0/16 + fd00:43::/112.
- Nodes: k8s-niobe (.10), k8s-trinity (.11), k8s-ghost (.12), all control-plane.

## Common operations

```sh
just reconcile                 # force Flux to pull from git
just kube sync hr              # force-reconcile kind (hr|ks|gitrepo|ocirepo|es)
just kube prune-pods
just talos validate <node>     # render + validate machine config
just talos apply-node <node|ip>
just talos generate-config     # regenerate talos machine configs from templates
just talos upgrade-k8s <version>
flux get ks -A && flux get hr -A
```

Node args accept name or IP; `just talos node-resolve` maps between them. Destructive talos recipes prompt for confirmation.

## Renovate / CI notes

- Renovate (`.renovaterc.json5`) bumps images (digest-pinned), chart tags in OCIRepositories, Talos/k8s versions, mise tools, and actions; commits are semantic (`feat:`, `fix:`, `chore:`, `ci:`).
- Workflows under `.github/workflows/` are path-filtered per tool (yamlfmt, kubeconform, tflint, flate…) — a PR can show unrelated skipped checks; that's expected.
