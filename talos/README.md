# Talos

Declarative [Talos Linux](https://www.talos.dev) machine configuration for the cluster, built from
composable multi-document patches. Nothing in this directory is applied automatically; configs are
rendered on demand and pushed to nodes with `talosctl`.

Cluster: 3 control-plane nodes (`k8s-niobe`, `k8s-trinity`, `k8s-ghost`), Cilium (kube-proxy and
CoreDNS disabled), SecureBoot metal installers from the [Image Factory](https://factory.talos.dev).

## Layout

| Path                                          | Purpose                                                            |
| --------------------------------------------- | ------------------------------------------------------------------ |
| `versions.yaml`                               | Renovate-managed `talosVersion` / `kubernetesVersion`               |
| `cluster.yaml.j2`                             | Documents applied to every node (base v1alpha1 + most documents)    |
| `deletions.yaml.j2`                           | `$patch: delete` documents applied to every node (Flannel)          |
| `controlplane.yaml.j2`                        | Control-plane-only documents, including `machine.type`              |
| `nodes/controlplane/<node>.yaml.j2`           | Per-node documents (hostname, link alias, address, logging)         |
| `nodes/controlplane/<node>.schematic.yaml.j2` | Optional per-node schematic override (complete file, not a delta)   |
| `schematic.yaml.j2`                           | Shared Image Factory schematic (AMD nodes)                          |
| `talosconfig`                                 | Client config (gitignored) — `$TALOSCONFIG` points here            |
| `mod.just`                                    | Recipes (`just talos ...`)                                          |

## Rendering

`just talos render-config <node>` builds the final machine config in four layers:

```
talosctl machineconfig patch <(cluster.yaml.j2) \
    -p @<(deletions.yaml.j2) \
    -p @<(controlplane.yaml.j2) \
    -p @<(nodes/controlplane/<node>.yaml.j2)
```

Each layer passes through `minijinja-cli` (strict Jinja templating; `--autoescape none` prevents
YAML value quoting, and the schematic ID / versions arrive as `-D` defines) and `op inject`
(1Password secret resolution) before `talosctl` merges them. Later patches strategically merge into
earlier ones: documents with the same `kind`/`name` are deep-merged, new documents are appended.

Conventions:

- **Directory placement is the single source of truth for a node's role.** The role patch is chosen
  by which `nodes/<role>/` directory contains the node file. Adding the first worker means creating
  `workers.yaml.j2` (with `machine: { type: worker }` and a `machine.ca`/`cluster.ca` block carrying
  `crt` only) plus `nodes/workers/<node>.yaml.j2`; rendering a worker before that fails loudly.
- **Secrets never live in this repo.** All sensitive values are `op://Zion/Talos/...` references
  resolved at render time by `op inject`.
- **`$patch: delete` documents live in `deletions.yaml.j2`**, because delete directives are only
  valid in patch layers, never in the base config.

## Secrets

The 1Password item **`Zion/Talos`** (Secure Note) holds the cluster PKI and tokens, base64-encoded
exactly as Talos stores them:

| Field                                 | Config target                            |
| ------------------------------------- | ---------------------------------------- |
| `MACHINE_CA_CRT` / `MACHINE_CA_KEY`   | `.machine.ca`                            |
| `MACHINE_TOKEN`                       | `.machine.token`                         |
| `CLUSTER_CA_CRT` / `CLUSTER_CA_KEY`   | `.cluster.ca`                            |
| `CLUSTER_AGGREGATORCA_CRT` / `_KEY`   | `.cluster.aggregatorCA`                  |
| `CLUSTER_ETCD_CA_CRT` / `_KEY`        | `.cluster.etcd.ca`                       |
| `CLUSTER_SERVICEACCOUNT_KEY`          | `.cluster.serviceAccount.key`            |
| `CLUSTER_TOKEN`                       | `.cluster.token`                         |
| `CLUSTER_ID` / `CLUSTER_SECRET`       | `.cluster.id` / `.cluster.secret`        |
| `CLUSTER_SECRETBOXENCRYPTIONSECRET`   | `.cluster.secretboxEncryptionSecret`     |

## Versions

Renovate bumps `versions.yaml` (the `talos-factory` preset owns `talosVersion`; the annotated
`kubernetesVersion` line tracks the kubelet image). `render-config` reads it and passes the values
as template defines, so the kubelet and control-plane component image tags update in lockstep.

## Schematics

The schematic defines the Image Factory build (system extensions). `just talos schematic-id <node>`
POSTs it to the factory and gets back a content-addressed ID, which is templated into the
`UnattendedInstallConfig` installer image and used by `download-image` and `upgrade-node`.

Resolution is per node: `nodes/controlplane/<node>.schematic.yaml.j2` wins when present, otherwise
the shared `schematic.yaml.j2` applies. Current state: shared AMD schematic for niobe/ghost, Intel
override for trinity.

## Gotchas

- `machine.ca` and `cluster.ca` merge as a cert+key **unit**: a patch supplying only `key` blanks
  `crt`. This is why `controlplane.yaml.j2` repeats the `crt` references alongside the keys.
- The kubelet block stays in v1alpha1: `.machine.kubelet` cannot coexist with the `KubeletConfig`
  document, and `extraMounts` (the `local-hostpath` mount) has no document equivalent.
- `cluster.controlPlane.endpoint` and `cluster.clusterName` must stay in the v1alpha1 `cluster:`
  block; the v1.14.0 legacy accessor (`K8sServiceAccountConfig` → `Endpoint()`) dereferences
  `ControlPlane` without a nil guard, so moving them to `KubeClusterConfig` crash-loops machined.
- The `buildkit.json` seccomp profile must stay in raw OCI `LinuxSeccomp` shape (flat
  `architectures` + `syscalls[names/action]`); Docker-style `archMap`/`includes`/`excludes` are
  silently dropped by containerd. It is scoped to rootless BuildKit build pods only.

## Common tasks

```sh
just talos render-config <node>        # render a node's full machine config to stdout
just talos validate <node>             # render and validate against the metal schema
just talos apply-node <node>           # render and apply (talosctl apply-config)
just talos upgrade-node <node>         # upgrade Talos using the node's schematic image
just talos upgrade-k8s <version>       # upgrade Kubernetes across the cluster
just talos download-image <version>    # fetch a metal ISO from the Image Factory
```

## Upgrading

Renovate bumps `versions.yaml`; per node, one at a time:

1. `just talos upgrade-node <node>` — installs the new installer image and reboots; the node keeps
   running its current config, which remains valid.
2. `just talos apply-node <node>` — pushes the rendered config for the new versions.

`kubernetesVersion` bumps flow through the rendered config itself (kubelet + control-plane
component images move in lockstep), so `upgrade-k8s` is only needed when applying out of band.

Verify a change before applying by diffing rendered output, or checking
`just talos render-config <node> | talosctl -n <node> apply-config -f /dev/stdin --dry-run`.
