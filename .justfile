set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']

# Bootstrap Recipes
[group('Bootstrap')]
mod bootstrap

# Talos Recipes
[group('Talos')]
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
    flux --namespace flux-system reconcile kustomization flux-system --with-source
