set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[private]
default:
    just --list talos

# Resolve a node argument given as name or IP; prints "<name> <ip>".
[private]
[script]
node-resolve n:
    for f in "{{ source_directory() }}"/nodes/controlplane/*.yaml.j2; do
        name="$(basename "$f" .yaml.j2)"
        ip="$(yq -r 'select(.kind == "LinkConfig") | .addresses[0].address' "$f" | head -1 | cut -d/ -f1)"
        if [[ "{{ n }}" == "$name" || "{{ n }}" == "$ip" ]]; then
            echo "$name $ip"
            exit 0
        fi
    done
    echo "unknown node: {{ n }}" >&2
    exit 1

[doc('Validate the rendered machine config for a node')]
[script]
validate node:
    just talos render-config "{{ node }}" | talosctl validate --mode metal --config /dev/stdin

[confirm('Apply Talos config to ' + node + ' [y|N]?')]
[doc('Render and apply Talos config to a node [name or IP; mode=auto; pass --insecure for a node in maintenance mode]')]
[script]
apply-node node mode='auto' *args:
    test -f "$TALOSCONFIG"
    command -v talosctl >/dev/null
    read -r name ip < <(just talos node-resolve {{ node }})
    if [[ " {{ args }} " != *" --insecure "* ]]; then
        talosctl --nodes "$ip" get machineconfig >/dev/null
        talosctl config info >/dev/null
    fi
    just talos render-config "$name" | talosctl -n "$ip" apply-config -f /dev/stdin --mode={{ mode }} {{ args }}

[confirm('Upgrade Talos on ' + node + ' [y|N]?')]
[doc('Upgrade Talos on a node [name or IP] using the installer image from the node schematic')]
[script]
upgrade-node node *args:
    test -f "$TALOSCONFIG"
    command -v talosctl >/dev/null
    read -r name ip < <(just talos node-resolve {{ node }})
    talosctl --nodes "$ip" get machineconfig >/dev/null
    talosctl config info >/dev/null
    talosctl -n "$ip" upgrade -i "$(just talos machine-image "$name")" -m powercycle --timeout=10m {{ args }}

[confirm('Upgrade Kubernetes to ' + version + ' [y|N]?')]
[doc('Upgrade Kubernetes version on the cluster')]
[script]
upgrade-k8s version:
    test -f "$TALOSCONFIG"
    command -v talosctl >/dev/null
    talosctl config info >/dev/null
    talosctl -n "$(talosctl config info -o yaml | yq -r -e '.endpoints[0]')" upgrade-k8s --to {{ version }}

[confirm('Reboot ' + node + ' [y|N]?')]
[doc('Reboot a node [name or IP]')]
[script]
reboot-node node *args:
    talosctl config info >/dev/null
    test -f "$TALOSCONFIG"
    command -v talosctl >/dev/null
    read -r _ ip < <(just talos node-resolve {{ node }})
    talosctl --nodes "$ip" reboot --mode powercycle {{ args }}

[confirm('Shut down ' + node + ' [y|N]?')]
[doc('Shut down a node [name or IP]')]
[script]
shutdown-node node *args:
    talosctl config info >/dev/null
    test -f "$TALOSCONFIG"
    command -v talosctl >/dev/null
    read -r _ ip < <(just talos node-resolve {{ node }})
    talosctl --nodes "$ip" shutdown --force {{ args }}

[confirm('This will DESTROY the cluster and reset nodes to maintenance mode [y|N]?')]
[doc('Reset nodes to maintenance mode [default wipes STATE+EPHEMERAL+local-hostpath; force=true wipes ALL partitions]')]
[script]
reset force='false' *args:
    command -v talosctl >/dev/null
    case "{{ force }}" in
        false) wipe="--system-labels-to-wipe STATE --system-labels-to-wipe EPHEMERAL --system-labels-to-wipe u-local-hostpath" ;;
        true)  wipe="" ;;
        *) echo "force must be 'true' or 'false', got '{{ force }}'" >&2; exit 1 ;;
    esac
    for node in $(talosctl config info -o yaml | yq -r -e '.nodes[]'); do
        talosctl --nodes "$node" reset --reboot ${wipe} --graceful=false --wait=false {{ args }}
    done

[doc('Download a Talos metal ISO from the Image Factory')]
[script]
download-image version node="":
    schematic="$(just talos schematic-id {{ node }})"
    curl -fL --remove-on-error --retry 5 --retry-delay 5 --retry-all-errors --progress-bar \
        -o "{{ source_directory() }}/talos-{{ version }}-${schematic:0:8}.iso" \
        "https://factory.talos.dev/image/${schematic}/{{ version }}/metal-amd64.iso"
    echo "Downloaded Talos {{ version }} schematic ${schematic}"

[doc('Render Talos machine config for a node')]
[script]
render-config node:
    read -r name _ < <(just talos node-resolve {{ node }})
    schematic="$(just talos schematic-id "$name")"
    role="controlplane"
    if [[ -f "{{ source_directory() }}/nodes/workers/$name.yaml.j2" ]]; then
        role="workers"
    fi
    talosctl machineconfig patch \
        <(just talos template "{{ source_directory() }}/cluster.yaml.j2" -D "schematic=${schematic}" $(just talos version-defines)) \
        -p @<(just talos template "{{ source_directory() }}/deletions.yaml.j2") \
        -p @<(just talos template "{{ source_directory() }}/${role}.yaml.j2" $(just talos version-defines)) \
        -p @<(just talos template "{{ source_directory() }}/nodes/${role}/$name.yaml.j2")

[private]
template file *args:
    minijinja-cli --autoescape none --strict "{{ file }}" {{ args }} | op inject

[private]
[script]
version-defines:
    echo -D talos_version="$(yq -r '.talosVersion' "{{ source_directory() }}/versions.yaml")" -D kubernetes_version="$(yq -r '.kubernetesVersion' "{{ source_directory() }}/versions.yaml")"

[private]
[script]
schematic-file node="":
    file="{{ source_directory() }}/schematic.yaml.j2"
    if [[ -n "{{ node }}" ]]; then
        for f in "{{ source_directory() }}"/nodes/*/{{ node }}.schematic.yaml.j2; do
            [[ -f "$f" ]] && file="$f"
        done
    fi
    echo "$file"

[private]
[script]
schematic-id node="":
    curl -fsS -X POST --data-binary @<(just talos template "$(just talos schematic-file {{ node }})") "https://factory.talos.dev/schematics" | jq -r '.id'

[private]
[script]
machine-image node:
    just talos render-config {{ node }} | yq -r -e 'select(.kind == "UnattendedInstallConfig") | .installer.image'
