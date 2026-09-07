# Talos

Declarative [Talos Linux](https://www.talos.dev) machine configuration for the cluster, built from
composable multi-document patches. Nothing in this directory is applied automatically; configs are
rendered on demand and pushed to nodes with `talosctl`.

## Layout

| Path                                          | Purpose                                                            |
| --------------------------------------------- | ------------------------------------------------------------------ |
| `cluster.yaml.j2`                             | Documents applied to every node                                   |
| `deletions.yaml.j2`                           | Documents removed from every node (Flannel)                       |
| `controlplane.yaml.j2`                        | Control-plane-only documents, including `machine.type`           |
| `nodes/controlplane/<node>.yaml.j2`           | Per-node documents (hostname, addresses, logging)                 |
| `nodes/controlplane/<node>.schematic.yaml.j2` | Optional per-node schematic override                              |
| `schematic.yaml.j2`                           | Shared Image Factory schematic                                    |
| `mod.just`                                    | Recipes (`just talos ...`)                                        |

## Rendering

`just talos render-config <node>` builds the final machine config in four layers:

```
talosctl machineconfig patch <(cluster.yaml.j2) \
    -p @<(deletions.yaml.j2) \
    -p @<(controlplane.yaml.j2) \
    -p @<(nodes/controlplane/<node>.yaml.j2)
```

Each layer passes through `minijinja-cli` and `op inject` before `talosctl` merges them. Later patches
strategically merge into earlier ones: documents with the same `kind`/`name` are deep-merged, and new
documents are appended. Kubernetes settings use Talos resource documents, including `KubeletConfig`,
`KubeNetworkConfig`, and `KubePrismConfig`.

NFS mounts use NFSv3 because the NAS does not support NFSv4. The NFS CSI storage class includes
`nolock` because Talos does not run `rpc.statd`.

Two conventions keep the layers honest:

- **Directory placement is the single source of truth for a node's role.** The role patch is chosen
  by which `nodes/<role>/` directory contains the node file.
- **Secrets never live in this repo.** All sensitive values are `op://Zion/Talos/...` references
  resolved at render time.

## Schematics

The schematic defines the Image Factory build. `just talos schematic-id <node>` POSTs it to the factory
and gets back a content-addressed ID, which is templated into the `UnattendedInstallConfig` installer
image and used by `download-image` and `upgrade-node`.

Resolution is per node: `nodes/controlplane/<node>.schematic.yaml.j2` wins when present, otherwise the
shared `schematic.yaml.j2` applies. The shared schematic is used by `k8s-niobe` and `k8s-ghost`; `k8s-trinity`
has an Intel-specific override.

## Common tasks

```sh
just talos render-config <node>        # render a node's full machine config to stdout
just talos validate <node>             # render and validate against the metal schema
just talos apply-node <node>           # render and apply (talosctl apply-config)
just talos upgrade-node <node>         # upgrade Talos using the node's schematic image
just talos upgrade-k8s <version>       # upgrade Kubernetes across the cluster
just talos download-image <version>    # fetch a metal ISO from the Image Factory
```

Verify changes before applying by diffing rendered output, then confirming
`just talos render-config <node> | talosctl -n "$(just talos node-resolve <node> | cut -d' ' -f2)" apply-config -f /dev/stdin --dry-run`
reports the expected diff on the target node.

Apply a configuration to one cordoned and drained node first, then verify the node and workloads
before proceeding with the remaining nodes.

```sh
just talos render-config <node> \
  | talosctl -n "$(just talos node-resolve <node> | cut -d' ' -f2)" \
      apply-config -f /dev/stdin --dry-run
```

The `local-hostpath` `UserVolumeConfig` backs OpenEBS's `openebs-hostpath` storage class at
`/var/mnt/local-hostpath`; the volume must remain in the rendered configuration. NFS CSI uses
NFSv3 with `nolock` because the NAS does not support NFSv4 and Talos does not run `rpc.statd`.
