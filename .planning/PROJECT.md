# home-ops

## What This Is

GitOps source of truth for the Zion Talos Kubernetes cluster running media, home automation, monitoring, networking, storage, GitLab, and related platform services.

## Current State

Shipped version: **v1.1 Storage & Migration Foundations** (completed 2026-05-30).

v1.1 replaced temporary foundations with durable platform paths:

- Longhorn was removed from GitOps and live cluster operation.
- Rook-Ceph/OpenEBS storage paths are established for current workloads.
- GitLab and GitLab Runner were rebuilt and validated on the new storage/CI path.
- kube-prometheus-stack is the production metrics/alerting path.
- VictoriaLogs remains the production log backend with native collector ingestion and `_msg` repair.
- Longhorn-only Talos source extensions (`iscsi-tools`, `util-linux-tools`) were removed; `nfs-utils` remains for active NFS workloads.

## Next Milestone Goals

No next milestone is defined yet. Use `/gsd-new-milestone` to gather requirements, research the next focus area, and generate the next roadmap.

## Archived Context

<details>
<summary>v1.1 project context before milestone archive</summary>

Milestone v1.1 changed the observability direction: v1.0 intentionally stayed on VictoriaMetrics while adopting onedr0p-style operational patterns, but v1.1 migrated metrics/alerting back to kube-prometheus-stack after memory-reduction gates and rollback boundaries were defined.

Longhorn removal was a hard v1.1 requirement. GitLab object data was disposable because GitLab was not in use yet, while other Longhorn PVCs required explicit disposition: preserve with `pv-migrate`, preserve with Kopia/VolSync restore, preserve with app-native migration, recreate/destroy, or decommission first.

GitLab already had Authentik OIDC wiring for the `groups` scope and `gitlab-admins` admin group, but v1.1 validated live GitLab behavior instead of assuming group-to-admin sync worked as intended. Because GitLab was not yet in use, a clean rebuild after Rook-Ceph readiness was acceptable once live evidence proved Gitaly contained no repositories that needed preservation.

</details>
