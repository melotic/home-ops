set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']

[private]
default:
    just -l talos

[doc('Generate Talos configuration with talhelper')]
generate-config:
    test -f talconfig.yaml
    test -f ../.sops.yaml
    test -f "$SOPS_AGE_KEY_FILE"
    command -v talhelper >/dev/null
    talhelper genconfig

[doc('Validate talconfig (read-only, no secrets)')]
validate:
    test -f talconfig.yaml
    test -f talenv.yaml
    command -v talhelper >/dev/null
    talhelper validate talconfig

[confirm('Apply Talos config to the node [y|N]?')]
[doc('Apply Talos config to a node [ip=required, mode=auto]')]
apply-node ip mode='auto':
    talosctl --nodes {{ ip }} get machineconfig
    talosctl config info
    test -f "$TALOSCONFIG"
    command -v talhelper >/dev/null && command -v talosctl >/dev/null && command -v yq >/dev/null
    talhelper gencommand apply --node {{ ip }} --extra-flags '--mode={{ mode }}' | bash

[confirm('Upgrade Talos on the node [y|N]?')]
[doc('Upgrade Talos on a single node [ip=required]')]
upgrade-node ip:
    talosctl --nodes {{ ip }} get machineconfig
    talosctl config info
    test -f "$TALOSCONFIG"
    command -v talhelper >/dev/null && command -v talosctl >/dev/null && command -v yq >/dev/null && command -v kubectl >/dev/null
    image="$(yq '.nodes[] | select(.ipAddress == "{{ ip }}") | .talosImageURL' talconfig.yaml)"; version="$(yq '.talosVersion' talenv.yaml)"; talhelper gencommand upgrade --node {{ ip }} --extra-flags "--image='$image:$version' --timeout=10m" | bash

[confirm('Upgrade Kubernetes on the cluster [y|N]?')]
[doc('Upgrade Kubernetes')]
upgrade-k8s:
    talosctl config info
    test -f "$TALOSCONFIG"
    command -v talhelper >/dev/null && command -v talosctl >/dev/null && command -v yq >/dev/null
    version="$(yq '.kubernetesVersion' talenv.yaml)"; talhelper gencommand upgrade-k8s --extra-flags "--to '$version'" | bash

[confirm('This will DESTROY the cluster and reset nodes to maintenance mode [y|N]?')]
[doc('Reset nodes back to maintenance mode [force=false full wipe; force=true lighter reset]')]
reset force='false':
    command -v talhelper >/dev/null
    wipe=""; if [ "{{ force }}" = "false" ]; then wipe="--system-labels-to-wipe STATE --system-labels-to-wipe EPHEMERAL"; fi; talhelper gencommand reset --extra-flags="--reboot $wipe --graceful=false --wait=false" | bash
