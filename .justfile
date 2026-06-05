set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']

# Bootstrap Recipes
[group: 'Bootstrap']
mod bootstrap

# Talos Recipes
[group: 'Talos']
mod talos

[private]
default:
    just --list

[doc('Force Flux to pull from Git')]
reconcile:
    test -f "$KUBECONFIG"
    command -v flux >/dev/null
    flux --namespace flux-system reconcile kustomization flux-system --with-source
