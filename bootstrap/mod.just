set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[private]
default:
    just --list bootstrap

[confirm('Bootstrap the Talos cluster [y|N]?')]
[doc('Apply Talos config to all nodes and bootstrap the cluster [nodes must be in maintenance mode]')]
[working-directory('..')]
[script]
talos:
    test -f "$TALOSCONFIG"
    command -v talosctl >/dev/null && command -v gum >/dev/null
    root="$(pwd)"
    first=""
    for f in talos/nodes/controlplane/*.yaml.j2; do
      node="$(basename "$f" .yaml.j2)"
      ip="$(yq -r 'select(.kind == "LinkConfig") | .addresses[0].address' "$f" | head -1 | cut -d/ -f1)"
      just log info "Applying Talos config to $node ($ip)" "mode" "insecure"
      just talos render-config "$node" | talosctl -n "$ip" --insecure apply-config -f /dev/stdin
      [ -z "$first" ] && first="$ip"
    done
    just log info "Bootstrapping Kubernetes, retrying until etcd is initialized" "node" "$first"
    until op="$(talosctl -n "$first" bootstrap 2>&1)" || [[ "$op" == *"AlreadyExists"* ]]; do
      just log info "Kubernetes bootstrap in progress, retrying in 10 seconds" "output" "$op"
      sleep 10
    done
    just log info "Fetching kubeconfig" "path" "$root"
    until talosctl -n "$first" kubeconfig "$root" --force; do sleep 10; done
    just log info "Talos cluster bootstrap complete"

[doc('Bootstrap apps into the Talos cluster')]
[working-directory('..')]
[script]
apps:
    test -f "$KUBECONFIG"
    test -f .sops.yaml
    test -f scripts/bootstrap-apps.sh
    test -f "$SOPS_AGE_KEY_FILE"
    command -v gum >/dev/null
    if [ "$(uname)" = "Darwin" ]; then
      bash_bin="$(command -v /opt/homebrew/bin/bash || command -v /usr/local/bin/bash || true)"
      [ -n "$bash_bin" ] || { echo "Unsupported bash version, run 'brew install bash' to upgrade" >&2; exit 1; }
    else
      bash_bin="bash"
    fi
    just log info "Bootstrapping apps into the cluster"
    "$bash_bin" scripts/bootstrap-apps.sh
    just log info "App bootstrap complete"
