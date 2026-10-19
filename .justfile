set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']

# Bootstrap Recipes
[group: 'Bootstrap']
mod bootstrap

# Install the tracked git hooks (secret scanning)
[group: 'Bootstrap']
hooks:
    git config core.hooksPath .githooks
    @echo "git hooks installed"

# Kube Recipes
[group: 'Kube']
mod kube "kubernetes"

# Talos Recipes
[group: 'Talos']
mod talos

[private]
default:
    just --list

[private]
log lvl msg *args:
    gum log -t rfc3339 -s -l "{{ lvl }}" "{{ msg }}" {{ args }}

[doc('Force Flux to pull from Git')]
reconcile:
    test -f "$KUBECONFIG"
    command -v flux >/dev/null
    flux --namespace flux-system reconcile kustomization flux-system --with-source
