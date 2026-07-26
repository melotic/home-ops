# 002: Dragonfly Operator

## Question

Given a single Dragonfly instance now backs several important services, when it becomes operator-managed with replicas, then do failover and durability improve enough to justify the operator?

## Live evidence

- One Dragonfly v1.39.0 pod in `database`, no authentication, 512 MiB limit.
- About 36.9 MiB live memory, 127.7 million commands over the observed lifetime, about 126 ops/s during inspection, zero evictions, zero pod restarts.
- Active numbered databases include Paperless, Harbor, Open WebUI, and four GitLab functions. GitLab queues and shared state make this more than a disposable cache.
- The mounted PVC contains about 306 MB of historical snapshots. `snapshot_cron` is empty and filenames are timestamped, so snapshots accumulate without pruning. The last save was tied to an earlier lifecycle event, not a current schedule.

## Operator comparison

| Option | Status | Fit |
|---|---|---|
| [Dragonfly Operator](https://github.com/dragonflydb/dragonfly-operator) v1.6.1 | Active, official, released June 2026 | Best fit. Same engine and DNS semantics; automatic primary failover, replication readiness gate, PDB, auth/TLS, PVC/S3 snapshots. |
| [OT-CONTAINER-KIT Redis Operator](https://github.com/OT-CONTAINER-KIT/redis-operator) v0.26.0 | Active and mature | Technically credible, but requires an engine migration and Sentinel/Redis topology for no demonstrated benefit. |
| [Valkey Operator](https://github.com/valkey-io/valkey-operator) v0.4.0 | Explicitly early development and not production-ready | Reject for this dependency tier. |
| Spotahome Redis Operator | Archived | Reject. |

The official Dragonfly HA model keeps one stable service pointed at the current primary: [HA docs](https://www.dragonflydb.io/docs/managing-dragonfly/high-availability). PVC snapshots restore after rescheduling but do not replace replication: [snapshot docs](https://www.dragonflydb.io/docs/managing-dragonfly/operator/snapshot-pvc).

## Migration preparation

- Set an explicit snapshot schedule and static `dbfilename` so the current PVC stops accumulating timestamped files.
- Replicate snapshots off-cluster and run a real restore drill with measured RPO/RTO.
- Alert on memory pressure, eviction, snapshot age/failure, restarts, and connectivity.
- Inventory which numbered databases hold queues, sessions, or shared state versus rebuildable caches.
- Preserve the current numbered-database allocation. Splitting instances is deferred because there is no measured contention or eviction pressure.

## Operator target

- Official Dragonfly Operator v1.6.1.
- One `Dragonfly` CR in `database`, three replicas across distinct nodes.
- `enableReplicationReadinessGate: true` and PDB `minAvailable: 2`.
- Preserve `--dbnum 16`, current service name, and client database allocations.
- Add authentication after all clients consume a shared ExternalSecret.
- Master-only PVC or S3-compatible snapshots with a static `dbfilename` and explicit schedule.
- Prometheus ServiceMonitor and alerts for unavailable primary and replication lag.

Resource cost at current sizing: requested memory rises from 64 MiB to 192 MiB and memory limits from 512 MiB to 1.5 GiB. Failover can still lose the newest acknowledged writes because replication is asynchronous.

## Blocker found

The v1.6.1 release advertises `oci://ghcr.io/dragonflydb/dragonfly-operator/helm`, but that package currently returns GHCR `404 name unknown`. The chart source at tag v1.6.1 renders successfully. Before production, either the upstream OCI package must be restored or home-ops must deliberately consume a pinned Git source/vendor the chart.

## Required rehearsal

1. Deploy the operator and a disposable three-replica CR.
2. Load keys across multiple logical DBs.
3. Delete the primary and verify the stable service promotes a synced replica with all keys intact.
4. Restart all replicas and verify snapshot restore.
5. Rehearse old-instance-to-new-instance transfer while clients are quiesced.

## Decision: ACCEPTED

Keep Dragonfly and adopt its official operator with three replicas. Preserve the existing service and logical database assignments, and gate cutover on snapshot restore and primary-failover rehearsals. Do not migrate to Redis or Valkey.
