set no-exit-message
set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']

[private]
default:
    just -l bootstrap

[confirm('Bootstrap the Talos cluster [y|N]?')]
[doc('Bootstrap the Talos cluster')]
talos:
    #!/usr/bin/env bash
    set -euo pipefail
    test -f .sops.yaml
    test -f "$SOPS_AGE_KEY_FILE"
    test -f talos/talconfig.yaml
    command -v talhelper >/dev/null && command -v talosctl >/dev/null && command -v sops >/dev/null
    root="$(pwd)"
    cd talos
    [ -f talsecret.sops.yaml ] || talhelper gensecret | sops --filename-override talos/talsecret.sops.yaml --encrypt /dev/stdin > talsecret.sops.yaml
    talhelper genconfig
    talhelper gencommand apply --extra-flags="--insecure" | bash
    until talhelper gencommand bootstrap | bash; do sleep 10; done
    until talhelper gencommand kubeconfig --extra-flags="$root --force" | bash; do sleep 10; done

[doc('Bootstrap apps into the Talos cluster')]
apps:
    test -f "$KUBECONFIG"
    test -f .sops.yaml
    test -f scripts/bootstrap-apps.sh
    test -f "$SOPS_AGE_KEY_FILE"
    bash scripts/bootstrap-apps.sh
