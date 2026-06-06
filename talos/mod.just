set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']

[private]
default:
    just --list talos

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
[doc('Apply Talos config to a node [ip=required, mode=auto; pass --insecure for a node in maintenance mode]')]
apply-node ip mode='auto' *args:
    #!/usr/bin/env bash
    set -euo pipefail
    test -f "$TALOSCONFIG"
    command -v talhelper >/dev/null && command -v talosctl >/dev/null
    if [[ " {{ args }} " != *" --insecure "* ]]; then
      talosctl --nodes {{ ip }} get machineconfig >/dev/null
      talosctl config info >/dev/null
    fi
    talhelper gencommand apply --node {{ ip }} --extra-flags '--mode={{ mode }} {{ args }}' | bash

[confirm('Upgrade Talos on the node [y|N]?')]
[doc('Upgrade Talos on a single node [ip=required]')]
upgrade-node ip *args:
    talosctl --nodes {{ ip }} get machineconfig
    talosctl config info
    test -f "$TALOSCONFIG"
    command -v talhelper >/dev/null && command -v talosctl >/dev/null
    talhelper gencommand upgrade --node {{ ip }} --extra-flags '--timeout=10m {{ args }}' | bash

[confirm('Reboot the node [y|N]?')]
[doc('Reboot a node [ip=required]')]
reboot-node ip *args:
    talosctl config info
    test -f "$TALOSCONFIG"
    command -v talosctl >/dev/null
    talosctl --nodes {{ ip }} reboot --mode powercycle {{ args }}

[confirm('Shut down the node [y|N]?')]
[doc('Shut down a node [ip=required]')]
shutdown-node ip *args:
    talosctl config info
    test -f "$TALOSCONFIG"
    command -v talosctl >/dev/null
    talosctl --nodes {{ ip }} shutdown --force {{ args }}

[confirm('Upgrade Kubernetes on the cluster [y|N]?')]
[doc('Upgrade Kubernetes')]
upgrade-k8s:
    talosctl config info
    test -f "$TALOSCONFIG"
    command -v talhelper >/dev/null && command -v talosctl >/dev/null
    talhelper gencommand upgrade-k8s | bash

[confirm('This will DESTROY the cluster and reset nodes to maintenance mode [y|N]?')]
[doc('Reset nodes to maintenance mode [default wipes STATE+EPHEMERAL+local-hostpath; force=true wipes ALL partitions]')]
reset force='false' *args:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v talhelper >/dev/null
    case "{{ force }}" in
      false) wipe="--system-labels-to-wipe STATE --system-labels-to-wipe EPHEMERAL --system-labels-to-wipe u-local-hostpath" ;;
      true)  wipe="" ;;
      *) echo "force must be 'true' or 'false', got '{{ force }}'" >&2; exit 1 ;;
    esac
    talhelper gencommand reset --extra-flags="--reboot ${wipe} --graceful=false --wait=false {{ args }}" | bash
