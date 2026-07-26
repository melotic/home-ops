# 001: Central Meilisearch

## Question

Given Karakeep and LibreChat each run Meilisearch v1.50.0, when they use one instance in `database`, then can they remain isolated without creating a worse operational boundary?

## Evidence

- Karakeep runs Meilisearch as a sidecar and uses the fixed `bookmarks` index. Live state: one index, about 42 MB used.
- LibreChat uses fixed `convos` and `messages` indexes in v0.8.7. Its new instance currently has no indexes and about 20 KB used.
- Both clients already accept a remote URL and API key: Karakeep uses `MEILI_ADDR`/`MEILI_MASTER_KEY`; LibreChat uses `MEILI_HOST`/`MEILI_MASTER_KEY`.
- Meilisearch API keys can restrict actions and indexes. The master key should only manage keys, not be shared with applications: [Meilisearch key model](https://www.meilisearch.com/docs/learn/security/master_api_keys).
- Tenant tokens are search-only and do not isolate indexing/settings operations, so they are not the right boundary between these two backends: [tenant tokens](https://www.meilisearch.com/docs/learn/security/tenant_tokens).
- Current requests total 125m CPU and 512 MiB memory, with 2 GiB combined memory limits. A shared 100m/512 MiB instance removes one container and 1 GiB of combined limit without materially changing requested memory.
- Both indexes are derived state. Karakeep can rebuild `bookmarks` from SQLite; LibreChat can rebuild `convos` and `messages` from its document database.

## Risks

- A shared restart affects both applications.
- A shared master key would let either app alter or delete the other's indexes.
- Upgrade cadence becomes shared, although both are already on the same release.
- Karakeep currently backs its index up with the app PVC. Centralization must either add a Meilisearch dump/snapshot job or explicitly treat indexes as rebuildable caches.

## Why the shared shape loses

- Index-scoped API keys can prevent direct cross-index access, but they do not isolate CPU, memory, the serial task queue, upgrades, or backups.
- Both applications call the credential `MEILI_MASTER_KEY` and upstream expects broad administrative behavior. Replacing that with scoped keys is technically possible, but it becomes our unsupported integration to maintain whenever either app adds an index or action.
- Karakeep documents version-sensitive upgrades and reindex recovery. LibreChat has its own [reset procedure](https://www.librechat.ai/docs/configuration/meilisearch#reset-synchronization). A shared instance forces both applications onto one upgrade and rollback window.
- [Dumps and snapshots](https://www.meilisearch.com/docs/learn/data_backup/snapshots_vs_dumps) cover the entire instance. Sharing removes per-application restore granularity even though both indexes can be rebuilt from their authoritative databases.
- A Karakeep or LibreChat reindex consumes the same [serial task queue](https://www.meilisearch.com/docs/capabilities/indexing/tasks_and_batches/async_operations) and can delay the other application.

## Minimal production shape

- Leave Karakeep's sidecar and LibreChat's StatefulSet application-owned.
- Treat both indexes as rebuildable projections. Back up Karakeep SQLite/assets and LibreChat's document database, not long-lived copies of every search index.
- Right-size or remove redundant Meilisearch backup retention before adding shared infrastructure.
- Reconsider centralization only after several more consumers make measured pod/storage savings larger than the shared failure and maintenance cost.

## Verdict: REJECTED

Keep them separate. Sharing is technically possible, but one fewer small pod is not worth coupling two otherwise independent applications.
