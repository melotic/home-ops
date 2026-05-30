---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: Storage & Migration Foundations
status: milestone-complete
last_updated: "2026-05-30T21:55:00.000Z"
last_activity: 2026-05-30
progress:
  total_phases: 10
  completed_phases: 10
  total_plans: 58
  completed_plans: 58
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-15)

**Core value:** The cluster must stay efficient, observable, and safe to change, even when hardware fails or workloads move.
**Current focus:** Milestone v1.1 archived — ready for next milestone definition

## Current Position

- Milestone v1.1 is archived to `.planning/milestones/v1.1-ROADMAP.md` and `.planning/milestones/v1.1-REQUIREMENTS.md`; active requirements were cleared for the next milestone cycle.
- Phase 17 and post-audit fixes completed: kube-prometheus-stack is the production metrics/alerting path, Alertmanager/Grafana/Kromgo/Rook consumers are rewired, VictoriaLogs remains with native collector `_msg` proof, VictoriaMetrics metrics/alerting GitOps and live resources are removed, Prometheus exporter coverage is restored, and historical metrics import is explicitly de-scoped.

Phase: 17 (kube-prometheus-stack-migration-logging-repair) — COMPLETE
Plan: 6 of 6
Status: Verified PASS 6/6; v1.1 milestone archived and ready for next milestone
Last activity: 2026-05-30

## Performance Metrics

**Velocity:**

- Total plans completed: 25
- Average duration: 0 min
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 4 | - | - |
| 05 | 3 | - | - |
| 09 | 3 | - | - |
| 14 | 8 | - | - |

**Recent Trend:**

- Last 5 plans: none
- Trend: Stable

| Phase 02 P01 | 43 | 2 tasks | 3 files |
| Phase 01 P03 | 6 | 2 tasks | 7 files |
| Phase 01 P04 | 2 | 2 tasks | 4 files |
| Phase 01 P02 | 177 | 2 tasks | 62 files |
| Phase 02 P02 | 83 | 2 tasks | 4 files |
| Phase 02 P03 | 61 | 2 tasks | 6 files |
| Phase 06 P02 | 0 min | 2 tasks | 3 files |
| Phase 06 P03 | 0 min | 2 tasks | 3 files |
| Phase 06 P04 | 0 min | 3 tasks | 0 files |
| Phase 06 P05 | 10 min | 3 tasks | 0 files |
| Phase 10 P04 | 3 min | 3 tasks | 9 files |
| Phase 10 P03 | 3 min | 1 tasks | 4 files |
| Phase 11 P01 | 31min | 1 tasks | 8 files |
| Phase 11 P02 | 8min | 2 tasks | 9 files |
| Phase 14 P01 | 16min | 3 tasks | 4 files |
| Phase 14 P03 | 59min | 3 tasks | 4 files |
| Phase 16 P01 | operator-gated | 1 tasks | 0 files |
| Phase 16 P04 | operator-gated | 3 tasks | 1 files |
| Phase 16 P04 | operator-gated | 3 tasks | 2 files |
| Phase 16 P02 | implementation | 3 tasks | 15 files |
| Phase 16 P05 | implementation | 3 tasks | 17 files |
| Phase 16 P03 | operator-gated | 3 tasks | 0 files |
| Phase 17 P01 | evidence | 2 tasks | 0 files |
| Phase 17 P02 | implementation | 3 tasks | 9 files |
| Phase 17 P03 | implementation | 2 tasks | 12 files |
| Phase 17 P04 | implementation | 3 tasks | 13 files |
| Phase 17 P05 | implementation | 3 tasks | 6 files |
| Phase 17 P06 | implementation | 3 tasks | 17 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.

Recent decisions affecting current work:

- [v1.1]: `home-ops` remains GitHub-based; do not add root `.gitlab-ci.yml` or repoint Flux to GitLab.
- [v1.1]: Internal Forgejo repository names must not be written to public planning or GitOps artifacts; use redacted evidence.
- [v1.1]: Longhorn removal is mandatory, but migration-gated and evidence-gated.
- [v1.1]: GitLab MinIO object data is disposable, but GitLab Gitaly is separate and may only be destroyed/rebuilt if live evidence proves no needed repositories exist.
- [v1.1]: kube-prometheus-stack migration is mandatory after memory, parity, and rollback gates pass; keep VictoriaLogs unless separately replaced.
- [v1.1]: GitLab Runner image-build proof must use BuildKit rootless under restricted PSS.
- [v1.1]: Ceph OSD bootstrap must use explicit safe devices or Talos Raw Volumes; avoid unsafe/system/Longhorn/Talos state devices and avoid Raw Volume names containing `ceph`.
- [v1.1]: Current nodes have one 1TB NVMe split into Talos `EPHEMERAL` and `u-longhorn`; there is no spare three-node OSD set, so Ceph bootstrap must reclaim Longhorn capacity node-by-node.
- [v1.1]: CNPG Pooler/monitoring refactor and CNPG storage migration are separate, backup-gated work.
- [v1.1]: Renovate branch automerge requires validation workflows on pushes to `renovate/**` as well as PRs to `main`.
- [v1.1]: Phase 10 selected `k8s-niobe` as the first reclaim node after live evidence refresh.
- [v1.1]: Phase 10 previously selected CNPG C2 as OpenEBS LocalPV hostpath destination, but the execution path is now superseded until topology blockers are resolved.
- [v1.1]: Phase 10 Plan 10-01 DR, Forejo, Kopia restore-drill, NAS, Azure, and live target evidence passed.
- [v1.1]: Phase 10 Plan 10-02 created non-destructive Rook-Ceph namespace/operator scaffolding only; CephCluster and OSD consumption remain deferred.
- [v1.1]: Phase 10 Plan 10-04 scaffolded OpenEBS LocalPV hostpath source only; OpenEBS remains suspended because no Talos-backed `/var/mnt/local-hostpath` exists.
- [v1.1]: Phase 10 Plan 10-04 kept OpenEBS/CNPG storage classes non-default and disabled OpenEBS snapshot CRDs so the existing snapshot-controller remains owner.
- [Phase 10]: Phase 10 Plan 10-03 staged inactive Rook-Ceph cluster manifests with k8s-niobe-only /dev/disk/by-partlabel/r-rook-osd selection, mon=1, mgr=1, replicated size=1, and non-default RBD/snapshot classes; Renovate later changed the manifest image to quay.io/ceph/ceph:v20.2.1, so regenerated Plan 10-10 requires compatibility proof before activation.
- [Phase 10]: Revised Plan 10-05 is non-destructive and must resolve CNPG/OpenEBS topology contradictions before any Longhorn, Talos, OpenEBS, or CephCluster mutation.
- [Phase 10]: Plan 10-05 recorded operator approval for an OpenEBS/CNPG redesign direction: migrate CNPG to OpenEBS one pod at a time, verify CNPG backups/WAL/archive first, and keep destructive authorization false until downstream plans are regenerated or amended.
- [Phase 10]: Downstream Plans 10-06 through 10-11 were regenerated to prove OpenEBS capacity, migrate CNPG to `openebs-hostpath`, evacuate `k8s-niobe`, reshape Talos to `rook-osd`, bootstrap constrained Rook-Ceph, and run RBD/snapshot smoke tests with explicit operator gates.
- [Phase 10]: Plan 10-06 completed CNPG DR preflight, recorded an operator-approved Talos `local-hostpath` UserVolumeConfig design, generated local Talos configs preserving both `local-hostpath` and `longhorn`, refreshed live evidence, and left live capacity proof to Plan 10-07.
- [Phase 10]: Initial Plan 10-07 operator apply on `k8s-niobe` confirmed `u-local-hostpath` cannot be created while `u-longhorn` consumes the disk; node, Longhorn, and CNPG remained healthy, but further node applies are blocked pending explicit Longhorn capacity reclaim.
- [Phase 10]: Plan 10-07 audit found 10-07/10-08/10-09 circular and unsafe as written; `10-07-OPERATOR-COMMAND-RUNBOOK.md` now holds the approved wait checks, backup gate, niobe evacuation shape, and commands that are explicitly not approved yet.
- [Phase 10]: Follow-up evidence at 2026-05-20T01:15:00Z showed `k8s-niobe` `u-local-hostpath` ready on `/dev/nvme0n1p5` and `u-longhorn` recreated on `/dev/nvme0n1p6`; CNPG and backup/WAL status were healthy, OpenEBS remained suspended, and Longhorn had 27 degraded volumes.
- [Phase 10]: Follow-up evidence at 2026-05-20T01:23:32Z showed Longhorn improved to 26 healthy, 1 degraded (`monitoring/vmsingle-vm-kube-stack`), and 4 classified detached unknown volumes.
- [Phase 10]: Follow-up evidence at 2026-05-20T01:28:24Z showed Longhorn degraded volumes cleared; remaining unknown volumes are classified detached volumes.
- [Phase 10]: Operator rejected parallel `k8s-trinity`/`k8s-ghost` reshape after risk review; remaining Plan 10-07 node order is sequential with `k8s-trinity` first and `k8s-ghost` only after CNPG primary moves away.
- [Phase 10]: Operator completed `k8s-trinity` and `k8s-ghost`; follow-up evidence at 2026-05-20T02:08:49Z showed all three nodes have `u-local-hostpath` and `u-longhorn` mounted, CNPG primary moved to `postgres-cluster-16` on `k8s-niobe`, and Longhorn was rebuilding with 24 degraded volumes.
- [Phase 10]: Deep Longhorn analysis at 2026-05-20T02:34-02:35Z found active degraded volumes rebuilding on current disk UUIDs, while the 4 classified unknown volumes have stopped replicas on old trinity/ghost disk UUIDs and may require stale replica cleanup if they remain stuck.
- [Phase 10]: Follow-up evidence at 2026-05-20T02:38:22Z showed Longhorn still at 24 healthy, 3 degraded, and 4 unknown; degraded volumes each have one `WO` current-disk replica, while the unknown volumes remain `attaching` with unsatisfied `volume-eviction-controller-*` tickets and stale old trinity/ghost disk UUID references.
- [Phase 10]: Follow-up evidence at 2026-05-20T21:31:16Z after the operator rebooted `k8s-ghost` showed all nodes Ready, CNPG healthy, all node mounts intact, Longhorn 27 healthy and 4 unknown, and the only remaining block as stale `volume-eviction-controller-*` tickets on the classified unknown volumes.
- [Phase 10]: Follow-up evidence at 2026-05-20T22:02:46Z showed `grafana-pvc` salvage succeeded by marking the old trinity replica failed/stopped and setting `salvageRequested=true` on the current niobe replica; remaining stale unknowns should use the same one-volume-at-a-time pattern.
- [Phase 10]: Follow-up evidence at 2026-05-20T22:11:29Z showed the operator completed stale Longhorn recovery by manually deleting failed replicas to kick off rebuilds; Longhorn returned to 27 healthy and 4 classified detached unknown volumes.
- [Phase 10]: PR #1100 merged OpenEBS activation as `ff859783`; latest observed Flux revision was `308bfb1f`, with OpenEBS installed and `phase10-openebs-probe` proving `openebs-hostpath` provisioning and cleanup.
- [Phase 10]: PR #1102 merged CNPG desired storageClass change as `c6c757cd`; Flux webhook reconciled it, and live CNPG is healthy on `openebs-hostpath` with backup/WAL status healthy. The old `postgres-cluster-16` Longhorn PV is retained and classified detached/unknown.
- [Phase 10]: Plan 10-09 completed Longhorn evacuation from `k8s-niobe`, removed the `k8s-niobe` Longhorn user volume, dropped old `u-longhorn` partition `/dev/nvme0n1p6`, and materialized ready Talos raw volume `r-rook-osd` at `/dev/disk/by-partlabel/r-rook-osd`; CNPG remained healthy with primary on `k8s-ghost`.
- [Phase 10]: Do not commit the intermediate Talos source patch from Plan 10-09; the operator confirmed it is not the final Talos state and should remain local until downstream Rook/Ceph state is settled.
- [Phase 10]: Plan 10-10 completed constrained Rook-Ceph bootstrap on `k8s-niobe`; Ceph `v20.2.1` raw-list discovery failed during empty bootstrap, so the cluster was cleaned and rebootstraped with Squid `v19.2.3-20250717`.
- [Phase 10]: Plan 10-10 uses persistent Ceph config for the one-OSD bootstrap: default pool size/min-size `1` and `mon_data_avail_warn` `20`; no-redundancy warnings remain visible and accepted.
- [Phase 10]: Plan 10-11 passed quiesced RBD/VolumeSnapshot smoke tests with temporary `phase10-smoke-*` resources, then cleaned up all Kubernetes resources, VolumeSnapshotContent objects, and smoke RBD images.
- [Phase 10]: Phase 10 closes with no production workload migrated to Ceph; Phase 11 must provide explicit migration gates before any production PVC moves to `ceph-block`.
- [Phase 11]: Plan 11-02 added source hardening for Kopia-native Azure sync, rclone `/volsync/**` exclusion, weekly/monthly VolSync retention, review-fixed backup/offsite/maintenance alerts, and SAS rotation documentation; preserved migrations remain blocked until live evidence rows are PASS.
- [Phase 11]: Operator clarified Azure offsite sync is non-blocking for Phase 11 migration gates; multi-scrobbler live NAS/Kopia evidence passed for checkpoint freshness, Kopia verify, sample restore, NFS path/excludes, retention, and alert acceptance, while one-time Azure seed job `kopia-azure-sync-seed-phase11-20260522020644` continues as hardening.
- [Phase 11]: Plan 11-03 migrated Harbor Trivy cache and multi-scrobbler to `ceph-block`; multi-scrobbler kept the stable PVC name via a retained-PV swap, and future preserved migrations should not use final `*-ceph` app PVC names unless explicitly approved.
- [Phase 11]: Plan 11-04 helper/runbook/plan now encode the stable-name retained-PV pattern: final app PVC names stay stable, temporary stage PVCs use `*-ceph-stage`, and HelmRelease `existingClaim` values remain unchanged.
- [Phase 11]: Plan 11-04 backup gates passed for beets, recyclarr, prowlarr, and radarr with fresh manual VolSync checkpoints, Kopia verify job `kopia-verify-phase11-20260522032147`, sample restore drills, NAS path evidence, retention, and alerts.
- [Phase 11]: Plan 11-04 migrated beets, recyclarr, prowlarr, and radarr to stable-name `ceph-block` PVCs; same-session validation passed and old Longhorn PVs/volumes plus stage PVCs were cleaned up.
- [Phase 11]: Azure offsite hardening verification passed after seed job `kopia-azure-sync-seed-phase11-20260522020644` completed and guarded job `kopia-azure-sync-verify-phase11-20260522041356` reported 6321 blobs / 30 GB in sync.
- [Phase 11]: Plan 11-05 migrated sonarr, lidarr, sabnzbd, and seerr to stable-name `ceph-block` PVCs; post-cutover VolSync backups, Kopia verify, restore drills, app smoke checks, and Flux convergence passed, then old Longhorn PVs/volumes plus stage PVCs were cleaned up.
- [Phase 11]: Plan 11-06 migrated slskd, tautulli, atuin, aurral, and paperless-ngx to stable-name `ceph-block` PVCs; backup gates, restore drills, app smoke checks, post-cutover VolSync, and Flux convergence passed, then old Longhorn PVs/volumes plus stage PVCs were cleaned up.
- [Phase 11]: Plan 11-07 Task 1 preflight found D-18, Longhorn capacity/health, CNPG, and backup gates acceptable; operator rebaselined Ceph `MON_DISK_LOW` as threshold noise because the mon store is tiny and the raw OSD is healthy; D-20 selected `k8s-trinity`; no mutation occurred.
- [Phase 11]: Plan 11-07 Task 2 approval recorded for `k8s-trinity`; operator stated they will run destructive Talos commands/apply and drain Longhorn replicas, so assistant must wait for operator live-step evidence before Rook/GitOps mutation.
- [Phase 11]: Plan 11-07 Talos source/manifests were prepared for `k8s-trinity`; generated config includes `RawVolumeConfig rook-osd`, ghost remains on Longhorn, and no live Talos apply was run by the assistant.
- [Phase 11]: Plan 11-07 completed second OSD expansion through PR #1126 (`c6a3bc58`); Flux reconciled `ceph-blockpool` size 2, Ceph has two OSDs up/in, and PGs are active+clean.
- [Phase 12]: Plan 12-02 completed W1 simple/app-config PVC migrations for ghidra-server, harbor-jobservice, dragonfly, home-assistant, and plex; all five stable PVC names now bind to `ceph-block`, controllers are Ready, stage PVCs are gone, and old W1 Longhorn volumes were deleted after same-session validation.
- [Phase 12]: Plan 12-06 completed full Rook-Ceph footprint readiness: 3 OSDs up/in, chart-default 3 mons and 2 mgrs live, all pools size 3/min_size 2, CephFS StorageClass and snapshot class present, policy-compliant CephFS smoke passed, and CNPG-07 closed as a D-05/D-07 do-not-migrate decision with CNPG healthy on `openebs-hostpath`. Remaining `MON_DISK_LOW` is mon d on `k8s-niobe`; the mon store is tiny, but niobe EPHEMERAL `/var` is 69 GB with containerd using most of the space.
- [Phase 12]: Niobe EPHEMERAL reprovision prep was completed under the operator-owned Talos boundary. Assistant-completed Kubernetes/Ceph prep promoted CNPG primary to `postgres-cluster-20` on `k8s-ghost`, purged niobe `osd.0`, cordoned/drained `k8s-niobe`, and suspended the `rook-ceph` operator HelmRelease with `rook-ceph-operator` scaled to 0 so it did not recreate the old OSD before disk reprovision. The temporary maintenance state was Ceph `HEALTH_WARN` with quorum `b,c`, 2 OSDs up/in and undersized/degraded PGs; CNPG 2/3 ready with `postgres-cluster-18` evicted from niobe.
- [Phase 12]: Niobe EPHEMERAL reprovision follow-up restored at 2026-05-24T15:35:32Z. Post-operator Talos work, niobe is Ready with `/var` on 137.37 GB EPHEMERAL and `r-rook-osd` as BlueStore. Rook was resumed, `osd.0` was recreated on niobe, and Ceph is `HEALTH_OK` with mons `b,c,d`, 3 OSDs up/in, and 81 PGs active+clean. CNPG recovered by destroying failed `postgres-cluster-18` with the CNPG plugin; `postgres-cluster-21` joined on niobe and CNPG is healthy with primary `postgres-cluster-20` plus standbys `postgres-cluster-19` and `postgres-cluster-21`.
- [Phase 12]: Plan 12-07 closed the VolSync Longhorn default UAT gap through PR #1151 (`5923a4de`): shared VolSync defaults now use `ceph-block`, `csi-ceph-blockpool`, and `openebs-hostpath`; redundant app-level storage/snapshot substitutions were removed; full pinned `flux-local` validation reported `156 passed`; Phase 12 UAT is 7/7 passed and verifier scored 5/5 must-haves.
- [Phase 17]: Completed kube-prometheus-stack migration through PRs #1258, #1260, #1261, #1263, #1264, #1268, #1270, #1274, and #1275; Prometheus/Alertmanager are production metrics/alerting, remaining consumers are rewired, VictoriaLogs remains with native collector `_msg` proof, VictoriaMetrics metrics/alerting resources are removed from GitOps and live cluster, exporter coverage is restored, and Longhorn-only Talos source extensions are removed.

### Roadmap Evolution

- Phase 7 added: Kyverno Tier-1 Enforce Promotion and Security Posture Closure.
- Phase 04-06 extracted to Phase 7 as 07-01 so Phase 5/6 routing is no longer blocked by the audit-window hold.
- Phase 8 completed: stayed on VictoriaMetrics, adopted onedr0p-style observability patterns, migrated Grafana to Grafana Operator, and applied safe cardinality pruning.
- Phase 7 completed: Kyverno policies 01, 07, and 08 are Enforce; policies 02-06 remain Audit; namespace PSA labels use explicit profile components.
- Phase 9 added: GitHub validation, Renovate branch CI, Talos/Longhorn reclaim inventory, Longhorn PVC disposition, and resource hygiene gates.
- Phase 10 added: first-node Longhorn replica evacuation, Talos raw OSD volume creation, constrained Rook-Ceph bootstrap, and RBD/snapshot smoke tests.
- Phase 11 added: initial Longhorn migration waves, migration runbooks, Kopia/VolSync checkpoints, disposable workload migration, and Ceph expansion to the next node.
- Phase 12 added: preserved stateful workload migration and full Rook-Ceph readiness across intended nodes.
- Phase 13 added: Longhorn reference removal and decommission gate.
- Phase 14 added: CNPG ownership refactor and Pooler/monitoring boundaries.
- Phase 15 added: GitLab rebuild or cutover on RGW object storage and Authentik OIDC admin group sync validation.
- Phase 16 added: GitLab Runner BuildKit rootless proof and redacted SCM migration closure.
- Phase 17 added: kube-prometheus-stack migration and Fluent Bit/VictoriaLogs `_msg` repair.
- Phase 14.1 inserted after Phase 14: CNPG rescue, GitOps cleanup, and operational recovery plan (URGENT)
- Phase 14.1 completed: stale CNPG desired-state was removed, Barman Cloud Plugin recovery was preserved, legacy `app` database/role and GitOps Secret source were retired, and restore drills passed.

### Pending Todos

Active pending todos:

- Harden VolSync Kopia NAS backups — captured 2026-05-17; folded into Phase 13 context for high-confidence decommission-safety items only.
- Right-size cluster resource requests and limits — captured 2026-05-24; live node usage shows substantial headroom and requests/limits need a full cluster pass.
- Reconcile Kyverno policy warning backlog — captured 2026-05-24; merged policies still produce many live warnings and may need manifest remediation plus Renovate support.
- Evaluate UniFi rsync backups over NFS — captured 2026-05-30; investigate UniFi Drive 4.2.2 rsync-over-SSH as a potential faster backup transport than current NFS-mounted jobs.

8 v1.0 carry-forward todos moved to `.planning/todos/deferred/v1.0/` are covered by v1.1 phases:

- Deploy PgBouncer for CNPG postgres-cluster — Phase 14
- Migrate CI image-builder from kaniko to BuildKit rootless — Phase 16
- Replace GitLab MinIO with Rook-Ceph S3 — Phase 15
- Fix AlertManager source links — Phase 17
- Tune GitLab runner CPU throttling — Phase 16
- Tighten CNPG Postgres topology — Phase 14
- Audit stale-pod metric queries — Phase 17
- Audit unscoped workload resources — Phase 9

### Blockers/Concerns

- First Ceph OSD capacity must be reclaimed from an existing Longhorn `u-longhorn` user volume after Longhorn replica evacuation; there is no spare three-node OSD set.
- Full Rook-Ceph capacity depends on incremental Longhorn migration and node-by-node OSD expansion.
- Longhorn removal has no simple rollback after CRDs/PVs/volumes are removed; Phase 13 is evidence-gated.
- GitLab Gitaly must not be treated as disposable unless live GitLab evidence proves no needed repositories exist.
- SCM closure evidence must remain redacted.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260525-veb | Restrict GitLab OIDC-created users and signup defaults with HelmRelease-only chart values; Web IDE single-origin fallback remains blocked because chart 10.0.0 has no HR value/template for it. | 2026-05-26 | b86e8dc2 | [260525-veb-resolve-these-gitlab-issues-check-the-re](./quick/260525-veb-resolve-these-gitlab-issues-check-the-re/) |
| gitlab-chart-10 | Merge GitLab HelmRepository into the HelmRelease, upgrade chart to 10.0.0, and use the chart-rendered webservice HTTPRoute against envoy-internal. | 2026-05-26 | 04a4effc, b74ad4a0 | [20260526-gitlab-chart-10-helmrepository-merge](./quick/20260526-gitlab-chart-10-helmrepository-merge/) |
| 260510-so1 | Review the rest of the dashboards and check they are not overly complex like the last PR was. | 2026-05-10 | f9c070a0 | [260510-so1-review-the-rest-of-the-dashboards-and-ch](./quick/260510-so1-review-the-rest-of-the-dashboards-and-ch/) |
| 260516-boy | PR 1073 CI deduplication replaced with scoped Renovate PR automerge. | 2026-05-16 | 6c945f0f | [260516-boy-take-a-look-at-pr-https-github-com-melot](./quick/260516-boy-take-a-look-at-pr-https-github-com-melot/) |

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Requirements | SEC-03 secret rotation workflow | Won't-do (v1) — no operational pain | 2026-04-27 |
| Requirements | SCM-02 migrated GitLab MR validation | Included in v1.1 Phase 16 | 2026-05-15 |
| Requirements | SCM-03 Forgejo migration/decommission | Included in v1.1 Phase 16 | 2026-05-15 |
| Storage | GitLab MinIO to Rook-Ceph S3 | Included in v1.1 Phase 15 | 2026-05-15 |
| Todos | 8 pending todos | Mapped into v1.1 phases | 2026-05-15 |
| Debug | Authentik/GitLab/Kaniko/CNPG debug sessions | Resolved or superseded before v1.0 close | 2026-05-15 |

## Session Continuity

Last session: 2026-05-30T21:55:00.000-05:00
Stopped at: v1.1 milestone archived; ready to start next milestone
Resume file: None

**Planned Phase:** None — next milestone definition workflow next

## Operator Next Steps

- Run `/gsd-new-milestone` when ready to define the next milestone.
- Treat live Talos/destructive node operations as operator-owned unless explicitly reassigned.
