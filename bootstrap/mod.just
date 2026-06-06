set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']

[private]
default:
    just --list bootstrap

[confirm('Bootstrap the Talos cluster [y|N]?')]
[doc('Bootstrap the Talos cluster')]
[working-directory('..')]
talos:
    #!/usr/bin/env bash
    set -euo pipefail
    test -f .sops.yaml
    test -f "$SOPS_AGE_KEY_FILE"
    test -f talos/talconfig.yaml
    command -v talhelper >/dev/null && command -v talosctl >/dev/null && command -v sops >/dev/null && command -v gum >/dev/null
    root="$(pwd)"
    cd talos
    just log info "Generating Talos secrets and machine config"
    if [ ! -f talsecret.sops.yaml ]; then
      tmp="$(mktemp .talsecret.sops.yaml.XXXXXX)"
      trap 'rm -f "$tmp"' EXIT
      talhelper gensecret | sops --filename-override talos/talsecret.sops.yaml --encrypt /dev/stdin > "$tmp"
      mv "$tmp" talsecret.sops.yaml
      trap - EXIT
    fi
    talhelper genconfig
    just log info "Applying Talos config to nodes" "mode" "insecure"
    talhelper gencommand apply --extra-flags="--insecure" | bash
    just log info "Bootstrapping Kubernetes, retrying until the API responds"
    until talhelper gencommand bootstrap | bash; do sleep 10; done
    just log info "Fetching kubeconfig" "path" "$root"
    until talhelper gencommand kubeconfig --extra-flags="$root --force" | bash; do sleep 10; done
    just log info "Talos cluster bootstrap complete"

[doc('Bootstrap apps into the Talos cluster')]
[working-directory('..')]
apps:
    test -f "$KUBECONFIG"
    test -f .sops.yaml
    test -f scripts/bootstrap-apps.sh
    test -f "$SOPS_AGE_KEY_FILE"
    command -v gum >/dev/null
    if [ "$(uname)" = "Darwin" ]; then test -f /opt/homebrew/bin/bash || test -f /usr/local/bin/bash || { echo "Unsupported bash version, run 'brew install bash' to upgrade" >&2; exit 1; }; fi
    just log info "Bootstrapping apps into the cluster"
    bash scripts/bootstrap-apps.sh
    just log info "App bootstrap complete"
